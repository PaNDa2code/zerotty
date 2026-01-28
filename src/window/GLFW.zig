const Window = @This();

keyboard_cb: ?*const fn (utf32: u32, press: bool) void = null,
xkb: Xkb = undefined,

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
    if (@import("builtin").mode == .Debug)
        _ = c.glfwSetErrorCallback(callbacks.errorCallback);

    _ = c.glfwInit();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

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
    errdefer self.xkb.deinit();

    _ = c.glfwSetWindowUserPointer(self.window, self);
    _ = c.glfwSetWindowSizeCallback(self.window, callbacks.windowSize);
    _ = c.glfwSetWindowCloseCallback(self.window, callbacks.windowClose);
    _ = c.glfwSetKeyCallback(self.window, callbacks.key);
    _ = c.glfwSetCharCallback(self.window, callbacks.char);

    c.glfwShowWindow(self.window);
}

pub fn setTitle(self: *Window, title: []const u8) !void {
    const title_z = try std.heap.c_allocator.dupeZ(u8, title);
    c.glfwSetWindowTitle(self.window, title_z);
    std.heap.c_allocator.free(title_z);
}

pub fn poll(_: *Window) void {
    c.glfwPollEvents();
}

pub fn close(self: *Window) void {
    self.xkb.deinit();
    c.glfwTerminate();
}

pub fn getHandles(self: *const Window) root.WindowHandles {
    return .{
        .window = self.window,
    };
}

const callbacks = struct {
    fn key(glfw_window: ?*c.GLFWwindow, _key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = mods;
        _ = action;
        _ = scancode;
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
        if (_key == c.GLFW_KEY_ESCAPE) {
            @as(*root.Window, @alignCast(@fieldParentPtr("w", window))).running = false;
            return;
        }
    }

    fn char(_: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
        var utf8: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &utf8) catch unreachable;
        std.log.debug("input: {s}", .{utf8[0..len]});
    }

    fn windowSize(glfw_window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
        window.height = @intCast(height);
        window.width = @intCast(width);
    }

    fn windowClose(glfw_window: ?*c.GLFWwindow) callconv(.c) void {
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
        @as(*root.Window, @alignCast(@fieldParentPtr("w", window))).running = false;
    }

    fn errorCallback(code: c_int, description: [*c]const u8) callconv(.c) void {
        std.log.scoped(.glfw).err(": {} {s}", .{ code, description });
    }
};

const std = @import("std");

const root = @import("root.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");
});
const Xkb = @import("input").keyboard.Xkb;

const Allocator = std.mem.Allocator;
