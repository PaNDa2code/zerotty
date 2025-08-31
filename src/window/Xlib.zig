const Window = @This();
pub const system = .Xlib;

socket: i32 = undefined,
title: []const u8,
height: u32,
width: u32,
display: *c.Display = undefined,
s: c_int = undefined,
w: c_ulong = undefined,
renderer: Renderer = undefined,
render_cb: ?*const fn (*Renderer) void = null,
resize_cb: ?*const fn (width: u32, height: u32) void = null,
keyboard_cb: ?*const fn (key: u8, press: bool) void = null,

exit: bool = false,
window_visable: bool = false,
wm_delete_window: c_ulong = 0,

pub fn new(title: []const u8, height: u32, width: u32) Window {
    return .{
        .title = title,
        .height = height,
        .width = width,
    };
}

pub fn open(self: *Window, allocator: Allocator) !void {
    const display = c.XOpenDisplay(null);
    const screen = c.DefaultScreen(display);

    self.display = display.?;
    self.s = screen;

    // x11 window is created inside opengl context creator
    self.renderer = try Renderer.init(self, allocator);

    const name = try allocator.dupeZ(u8, self.title);
    _ = c.XStoreName(@ptrCast(display), self.w, name.ptr);
    allocator.free(name);

    var wm_delete_window = c.XInternAtom(@ptrCast(self.display), "WM_DELETE_WINDOW", 0);
    _ = c.XSetWMProtocols(@ptrCast(self.display), self.w, &wm_delete_window, 1);

    self.wm_delete_window = wm_delete_window;
}

fn resizeCallBack(self: *Window, height: u32, width: u32) !void {
    self.height = height;
    self.width = width;
    try self.renderer.resize(width, height);
}

pub fn messageLoop(self: *Window) void {
    while (!self.exit) {
        self.pumpMessages();
    }
}

pub fn pumpMessages(self: *Window) void {
    _ = c.XSelectInput(self.display, self.w, c.ExposureMask | c.StructureNotifyMask | c.KeyPressMask);

    var event: c.XEvent = undefined;
    const pending = c.XPending(self.display);
    var i: c_int = 0;
    while (i < pending) : (i += 1) {
        _ = c.XNextEvent(self.display, &event);

        switch (event.type) {
            c.Expose => {
                self.window_visable = true;
            },
            c.KeyPress => {
                const keycode = event.xkey.keycode;
                if (keycode == 9)
                    self.exit = true;
                if (self.keyboard_cb) |cb| {
                    cb(@intCast(keycode), true);
                }
            },
            c.KeyRelease => {
                const keycode = event.xkey.keycode;
                if (self.keyboard_cb) |cb| {
                    cb(@intCast(keycode), false);
                }
            },
            c.ClientMessage => {
                if (event.xclient.data.l[0] == self.wm_delete_window) {
                    self.exit = true;
                    break;
                }
            },
            c.ConfigureNotify => {
                const height: u32 = @intCast(event.xconfigure.height);
                const width: u32 = @intCast(event.xconfigure.width);
                self.resizeCallBack(height, width) catch |e|
                    std.log.err("Window resize failed: {}", .{e});
                if (self.resize_cb) |cb| {
                    cb(width, height);
                }
            },
            else => {},
        }
    }
    if (self.window_visable)
        if (self.render_cb) |cb|
            cb(&self.renderer);
}

pub fn close(self: *Window) void {
    self.renderer.deinit();
    _ = c.XDestroyWindow(@ptrCast(self.display), self.w);
    _ = c.XCloseDisplay(@ptrCast(self.display));
}

const std = @import("std");
const Renderer = @import("../renderer/root.zig");

const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
});
