const Window = @This();
pub const system = .Xcb;

connection: *c.xcb_connection_t = undefined,
screen: *c.xcb_screen_t = undefined,
window: c.xcb_window_t = undefined,
renderer: Renderer = undefined,
render_cb: ?*const fn (*Renderer) void = null,
resize_cb: ?*const fn (width: u32, height: u32) void = null,

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
        self.screen.*.white_pixel,
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
        800,
        600, // width, height
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
            c.XCB_CLIENT_MESSAGE => {},
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

const std = @import("std");
const Renderer = @import("../renderer/root.zig");

const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("X11/keysym.h");
});
