const Window = @This();
pub const system = .Xcb;

connection: *c.xcb_connection_t = undefined,
screen: *c.xcb_screen_t = undefined,
window: c.xcb_window_t = undefined,
renderer: Renderer = undefined,
render_cb: ?*const fn (*Renderer) void = null,
resize_cb: ?*const fn (width: u32, height: u32) void = null,
keyboard_cb: ?*const fn (key: u8, press: bool) void = null,

wm_delete_window_atom: c.xcb_atom_t = 0,

exit: bool = false,
title: []const u8,
height: u32,
width: u32,

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

    const setup = c.xcb_get_setup(self.connection);
    self.screen = c.xcb_setup_roots_iterator(setup).data.?;

    const window_id = c.xcb_generate_id(self.connection);
    self.window = window_id;

    const value_mask: u32 = c.XCB_CW_BACK_PIXEL | c.XCB_CW_EVENT_MASK;
    const value_list = [_]u32{
        self.screen.*.black_pixel,
        c.XCB_EVENT_MASK_EXPOSURE |
            c.XCB_EVENT_MASK_KEY_PRESS |
            c.XCB_EVENT_MASK_STRUCTURE_NOTIFY,
    };

    _ = c.xcb_create_window(
        self.connection,
        self.screen.*.root_depth, // depth
        window_id, // window id
        self.screen.*.root, // parent window
        0,
        0, // x, y
        @intCast(self.width),
        @intCast(self.height), // width, height
        0, // border width
        c.XCB_WINDOW_CLASS_INPUT_OUTPUT,
        self.screen.*.root_visual,
        value_mask,
        &value_list,
    );

    // Set window title
    const title = try allocator.dupeZ(u8, self.title);
    defer allocator.free(title);
    _ = c.xcb_change_property(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        window_id,
        c.XCB_ATOM_WM_NAME,
        c.XCB_ATOM_STRING,
        8,
        @intCast(title.len),
        title.ptr,
    );

    // Map (show) the window
    _ = c.xcb_map_window(self.connection, window_id);

    // Flush all commands
    _ = c.xcb_flush(self.connection);

    // var img = try zigimg.ImageUnmanaged.fromMemory(allocator, assets.icons.@"logo_32x32.png");
    // defer img.deinit(allocator);
    //
    // try img.convert(allocator, .bgra32);
    //
    // const pixels = img.pixels.asBytes();
    //
    // var buffer = try allocator.alloc(u8, pixels.len + 8);
    // defer allocator.free(buffer);
    //
    // std.mem.writeInt(u32, buffer[0..4], @intCast(img.width), .little);
    // std.mem.writeInt(u32, buffer[4..8], @intCast(img.height), .little);
    //
    // @memcpy(buffer[8..], pixels);
    //
    // const data_len = pixels.len + 8;
    //
    // const net_wm_icon_atom = get_atom(self.connection, "_NET_WM_ICON") orelse unreachable;
    // const cardinal_atom = get_atom(self.connection, "CARDINAL") orelse unreachable;

    const wm_protocols_atom = get_atom(self.connection, "WM_PROTOCOLS") orelse unreachable;
    self.wm_delete_window_atom = get_atom(self.connection, "WM_DELETE_WINDOW") orelse unreachable;

    // _ = c.xcb_change_property(
    //     self.connection,
    //     c.XCB_PROP_MODE_REPLACE,
    //     self.window,
    //     net_wm_icon_atom,
    //     cardinal_atom,
    //     32,
    //     @intCast(data_len / 4),
    //     buffer.ptr,
    // );

    _ = c.xcb_change_property(
        self.connection,
        c.XCB_PROP_MODE_REPLACE,
        self.window,
        wm_protocols_atom,
        c.XCB_ATOM_ATOM,
        32,
        1,
        &self.wm_delete_window_atom,
    );

    self.renderer = try Renderer.init(self, allocator);
}

fn resizeCallBack(self: *Window, height: u32, width: u32) !void {
    self.height = height;
    self.width = width;
    try self.renderer.resize(width, height);
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
            },
            c.XCB_DESTROY_NOTIFY => {
                self.exit = true;
            },
            c.XCB_CLIENT_MESSAGE => {
                if (@as(*c.xcb_client_message_event_t, @ptrCast(event)).data.data32[0] == self.wm_delete_window_atom)
                    self.exit = true;
            },
            else => {},
        }

        // Free the event after processing
        std.c.free(event);
    }
}
pub fn close(self: *Window) void {
    _ = c.xcb_destroy_window(self.connection, self.window);
    c.xcb_disconnect(self.connection);
    self.renderer.deinit();
}

fn get_atom(conn: *c.xcb_connection_t, atom_name: []const u8) ?c.xcb_atom_t {
    const cookie = c.xcb_intern_atom(conn, 0, @intCast(atom_name.len), @ptrCast(atom_name.ptr));
    const replay = c.xcb_intern_atom_reply(conn, cookie, null) orelse return null;
    defer c.free(replay);
    return replay.*.atom;
}

const std = @import("std");
const Renderer = @import("../renderer/root.zig");

const Allocator = std.mem.Allocator;

// const zigimg = @import("zigimg");
const assets = @import("assets");
const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("X11/keysym.h");
    @cInclude("stdlib.h");
});
