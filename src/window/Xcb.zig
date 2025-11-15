const Window = @This();
pub const system = .Xcb;

connection: *c.xcb_connection_t = undefined,
screen: *c.xcb_screen_t = undefined,
window: c.xcb_window_t = undefined,
renderer: Renderer = undefined,
render_cb: ?*const fn (*Renderer) void = null,
resize_cb: ?*const fn (width: u32, height: u32) void = null,

opacity_atom: u32 = 0,

xkb: Xkb = undefined,
keyboard_cb: ?*const fn (utf32: u32, press: bool) void = null,

wm_delete_window_atom: c.xcb_atom_t = 0,
wm_name_atom: c.xcb_atom_t = 0,

exit: bool = false,
title: []const u8,
height: u32,
width: u32,

const log = std.log.scoped(.window);

pub fn new(title: []const u8, height: u32, width: u32) Window {
    return .{
        .title = title,
        .height = height,
        .width = width,
    };
}

pub fn open(self: *Window, allocator: Allocator) !void {
    self.connection = c.xcb_connect(null, null).?;
    if (c.xcb_connection_has_error(self.connection) != 0) {
        return error.XCBConnectionError;
    }

    const setup = c.xcb_get_setup(self.connection) orelse return error.NoSetup;
    self.screen = c.xcb_setup_roots_iterator(setup).data orelse return error.NoScreen;

    const window_id = c.xcb_generate_id(self.connection);
    self.window = window_id;

    // https://stackoverflow.com/questions/43218127/x11-xlib-xcb-creating-a-window-requires-border-pixel-if-specifying-colormap-wh
    const value_mask: u32 = c.XCB_CW_BACK_PIXEL | c.XCB_CW_EVENT_MASK | c.XCB_CW_COLORMAP | c.XCB_CW_BORDER_PIXEL;

    const visual = get_argb_visual(self.screen) orelse return error.NoVisual;

    const colormap_id = c.xcb_generate_id(self.connection);

    const colormap_cookie = c.xcb_create_colormap_checked(
        self.connection,
        c.XCB_COLORMAP_ALLOC_NONE,
        colormap_id,
        self.screen.*.root,
        visual,
    );

    if (c.xcb_request_check(self.connection, colormap_cookie)) |err| {
        defer c.free(err);
        return error.ColorMapCreationFailed;
    }

    const value_list = [_]u32{
        0,
        0,
        c.XCB_EVENT_MASK_EXPOSURE |
            c.XCB_EVENT_MASK_KEY_PRESS |
            c.XCB_EVENT_MASK_STRUCTURE_NOTIFY,
        colormap_id,
    };

    const create_cookie = c.xcb_create_window_checked(
        self.connection,
        32, // depth
        window_id, // window id
        self.screen.*.root, // parent window
        0,
        0, // x, y
        @intCast(self.width),
        @intCast(self.height), // width, height
        0, // border width
        c.XCB_WINDOW_CLASS_INPUT_OUTPUT,
        visual,
        value_mask,
        &value_list,
    );

    if (c.xcb_request_check(self.connection, create_cookie)) |err| {
        std.debug.print("err: {}\n", .{err.*.error_code});
        defer c.free(err);
        return error.CreateWindowFailed;
    }

    const title = try allocator.dupeZ(u8, self.title);
    defer allocator.free(title);

    const title_cookie = c.xcb_change_property_checked(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        window_id,
        c.XCB_ATOM_WM_NAME,
        c.XCB_ATOM_STRING,
        8,
        @intCast(title.len),
        title.ptr,
    );

    if (c.xcb_request_check(self.connection, title_cookie)) |err| {
        defer c.free(err);
        return error.SetTitleFailed;
    }

    const map_cookie = c.xcb_map_window_checked(self.connection, window_id);

    if (c.xcb_request_check(self.connection, map_cookie)) |err| {
        defer c.free(err);
        return error.MapWindowFailed;
    }

    if (c.xcb_flush(self.connection) <= 0) {
        return error.FlushFailed;
    }

    var img = try zigimg.Image.fromMemory(allocator, assets.icons.@"logo_32x32.png");
    defer img.deinit(allocator);

    try img.convert(allocator, .bgra32);

    const pixels = img.pixels.asBytes();

    var buffer = try allocator.alloc(u8, pixels.len + 8);
    defer allocator.free(buffer);

    std.mem.writeInt(u32, buffer[0..4], @intCast(img.width), .little);
    std.mem.writeInt(u32, buffer[4..8], @intCast(img.height), .little);

    @memcpy(buffer[8..], pixels);

    const data_len = pixels.len + 8;

    const net_wm_icon_atom = get_atom(self.connection, "_NET_WM_ICON") orelse unreachable;
    const cardinal_atom = get_atom(self.connection, "CARDINAL") orelse unreachable;
    self.wm_name_atom = get_atom(self.connection, "WM_NAME") orelse unreachable;

    const wm_protocols_atom = get_atom(self.connection, "WM_PROTOCOLS") orelse unreachable;
    self.wm_delete_window_atom = get_atom(self.connection, "WM_DELETE_WINDOW") orelse unreachable;

    _ = c.xcb_change_property(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        self.window,
        net_wm_icon_atom,
        cardinal_atom,
        32,
        @intCast(data_len / 4),
        buffer.ptr,
    );

    const wm_cookie = c.xcb_change_property_checked(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        self.window,
        wm_protocols_atom,
        c.XCB_ATOM_ATOM,
        32,
        1,
        &self.wm_delete_window_atom,
    );

    if (c.xcb_request_check(self.connection, wm_cookie)) |err| {
        defer c.free(err);
        return error.SetProtocolsFailed;
    }

    self.opacity_atom = get_atom(self.connection, "_NET_WM_WINDOW_OPACITY") orelse return;

    self.xkb = try Xkb.init();
    self.renderer = try Renderer.init(self, allocator);
}

/// set window opacity value from 0.0 to 1.0
pub fn setOpacity(self: *Window, value: f32) !void {
    if (value < 0.0 or value > 1.0) {
        return error.InvalidValue;
    }

    const opacity: u32 = @intFromFloat(@as(f64, 0xFFFFFFFF) * value);
    const opacity_cookie = c.xcb_change_property_checked(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        self.window,
        self.opacity_atom,
        c.XCB_ATOM_CARDINAL,
        32,
        1,
        &opacity,
    );

    if (c.xcb_request_check(self.connection, opacity_cookie)) |err| {
        defer c.free(err);
        return error.SetOpacityFailed;
    }
}

fn resizeCallBack(self: *Window, height: u32, width: u32) !void {
    self.height = height;
    self.width = width;
    try self.renderer.resize(width, height);
}

pub fn setTitle(self: *Window, title: []const u8) !void {
    const title_cookie = c.xcb_change_property_checked(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        self.window,
        c.XCB_ATOM_WM_NAME,
        c.XCB_ATOM_STRING,
        8,
        @intCast(title.len),
        title.ptr,
    );

    if (c.xcb_request_check(self.connection, title_cookie)) |err| {
        defer c.free(err);
        return error.SetTitleFailed;
    }
}

pub fn pumpMessages(self: *Window) void {
    while (c.xcb_poll_for_event(self.connection)) |event| {
        const response_type = event.*.response_type & 0x7F;

        switch (response_type) {
            c.XCB_EXPOSE => {},
            c.XCB_KEY_PRESS => {
                const key_press: *c.xcb_key_press_event_t = @ptrCast(event);
                if (key_press.detail == 9)
                    self.exit = true;
                const sym = Xkb.c.xkb_state_key_get_one_sym(self.xkb.state, @intCast(key_press.detail));
                const utf32 = Xkb.c.xkb_keysym_to_utf32(sym);

                if (self.keyboard_cb) |cb| cb(utf32, true);
            },
            c.XCB_KEY_RELEASE => {
                const key_release: *c.xcb_key_release_event_t = @ptrCast(event);
                _ = Xkb.c.xkb_state_update_key(self.xkb.state, key_release.detail, Xkb.c.XKB_KEY_UP);
            },
            c.XCB_DESTROY_NOTIFY => {
                self.exit = true;
            },
            c.XCB_CLIENT_MESSAGE => {
                if (@as(*c.xcb_client_message_event_t, @ptrCast(event)).data.data32[0] == self.wm_delete_window_atom)
                    self.exit = true;
            },
            c.XCB_CONFIGURE_NOTIFY => {
                const cfg: *c.xcb_configure_notify_event_t = @ptrCast(event);
                self.resizeCallBack(@intCast(cfg.height), @intCast(cfg.width)) catch unreachable;
            },
            else => {},
        }

        // Free the event after processing
        std.c.free(event);
    }
}
pub fn close(self: *Window) void {
    self.renderer.deinit();

    const cookie = c.xcb_destroy_window_checked(self.connection, self.window);
    if (c.xcb_request_check(self.connection, cookie)) |err| {
        log.debug("xcb_destroy_window_checked: {}", .{err.*.error_code});
        c.free(err);
    }

    c.xcb_disconnect(self.connection);
}

fn get_argb_visual(screen: *c.xcb_screen_t) ?u32 {
    var visual_iter = c.xcb_screen_allowed_depths_iterator(screen);
    while (visual_iter.rem != 0) : (c.xcb_depth_next(&visual_iter)) {
        const depth = visual_iter.data;

        if (depth.*.depth != 32) continue;

        var visual_list = c.xcb_depth_visuals_iterator(depth);

        while (visual_list.rem != 0) : (c.xcb_visualtype_next(&visual_list)) {
            if (visual_list.data.*._class == c.XCB_VISUAL_CLASS_TRUE_COLOR)
                return visual_list.data.*.visual_id;
        }
    }
    return null;
}

fn get_atom(conn: *c.xcb_connection_t, atom_name: []const u8) ?c.xcb_atom_t {
    const cookie = c.xcb_intern_atom(conn, 0, @intCast(atom_name.len), @ptrCast(atom_name.ptr));
    const replay = c.xcb_intern_atom_reply(conn, cookie, null) orelse return null;
    defer c.free(replay);
    return replay.*.atom;
}

const std = @import("std");
const Renderer = @import("../renderer/root.zig");
const Xkb = @import("../input/Xkb.zig");

const Allocator = std.mem.Allocator;

const zigimg = @import("zigimg");
const assets = @import("assets");
const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("X11/keysym.h");
    @cInclude("stdlib.h");
});
