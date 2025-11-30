const Window = @This();
pub const system = .GLFW;

renderer: Renderer = undefined,
render_cb: ?*const fn (*Renderer) void = null,
resize_cb: ?*const fn (width: u32, height: u32) void = null,

xkb: Xkb = undefined,
keyboard_cb: ?*const fn (utf32: u32, press: bool) void = null,

exit: bool = false,
title: []const u8,
height: u32,
width: u32,

window: *c.GLFWwindow = undefined,

pub fn new(title: []const u8, height: u32, width: u32) Window {
    return .{
        .title = title,
        .height = height,
        .width = width,
    };
}

pub fn open(self: *Window, allocator: Allocator) !void {
    _ = c.glfwInit();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    self.exit = false;

    const title = try allocator.dupeZ(u8, self.title);
    defer allocator.free(title);

    self.window = c.glfwCreateWindow(
        @intCast(self.width),
        @intCast(self.height),
        title.ptr,
        null,
        null,
    ) orelse return error.GLFWCreateWindow;

    var fb_w: c_int = 0;
    var fb_h: c_int = 0;
    c.glfwGetFramebufferSize(self.window, &fb_w, &fb_h);

    self.width = @intCast(fb_w);
    self.height = @intCast(fb_h);

    self.xkb = try Xkb.init();
    self.renderer = try Renderer.init(self, allocator);

    _ = c.glfwSetWindowUserPointer(self.window, self);

    _ = c.glfwSetWindowSizeCallback(self.window, struct {
        fn callback(glfw_window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
            const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
            window.height = @intCast(height);
            window.width = @intCast(width);
            window.renderer.resize(@intCast(width), @intCast(height)) catch @panic("resize failed");
        }
    }.callback);

    _ = c.glfwSetWindowCloseCallback(self.window, struct {
        fn callback(glfw_window: ?*c.GLFWwindow) callconv(.c) void {
            const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
            window.exit = true;
        }
    }.callback);

    _ = c.glfwSetKeyCallback(self.window, struct {
        fn callback(glfw_window: ?*c.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.c) void {
            _ = mods;
            _ = scancode;
            const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
            if (key == c.GLFW_KEY_ESCAPE) {
                window.exit = true;
                return;
            }

            if (key == c.GLFW_KEY_ENTER) {
                if (window.keyboard_cb) |cb| {
                    cb('\n', action == c.GLFW_PRESS);
                }
            }
        }
    }.callback);

    _ = c.glfwSetCharCallback(self.window, struct {
        fn callback(glfw_window: ?*c.GLFWwindow, codepoint: u32) callconv(.c) void {
            const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
            if (window.keyboard_cb) |cb| {
                cb(codepoint, true);
            }
        }
    }.callback);
}

pub fn setTitle(self: *Window, title: []const u8) !void {
    const title_z = try std.heap.c_allocator.dupeZ(u8, title);
    c.glfwSetWindowTitle(self.window, title_z);
    std.heap.c_allocator.free(title_z);
}

pub fn pumpMessages(_: *Window) void {
    c.glfwPollEvents();
}

pub fn close(self: *Window) void {
    self.renderer.deinit();
    c.glfwTerminate();
}

const std = @import("std");

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});
const Renderer = @import("../renderer/root.zig");
const Xkb = @import("../input/Xkb.zig");

const Allocator = std.mem.Allocator;
