const Window = @This();

keyboard_cb: ?*const fn (utf32: u32, press: bool) void = null,

title: []const u8,
height: u32,
width: u32,

window: *c.GLFWwindow = undefined,

event_queue: *root.EventQueue = undefined,

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

pub fn close(_: *Window) void {
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
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
        // const root_window = @as(*root.Window, @alignCast(@fieldParentPtr("w", window)));

        if (_key == c.GLFW_KEY_ESCAPE) {
            window.event_queue.push(.close) catch unreachable;
            return;
        }

        const event = root.WindowEvent{
            .input = .{
                .keyboard = .{
                    .type = if (action == c.GLFW_PRESS)
                        .press
                    else if (action == c.GLFW_REPEAT)
                        .repeat
                    else
                        .release,
                    .code = @intCast(scancode),
                },
            },
        };

        window.event_queue.push(event) catch unreachable;
    }

    fn char(glfw_window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));

        const event = root.WindowEvent{
            .input = .{
                .utf8_codepoint = @intCast(codepoint),
            },
        };

        window.event_queue.push(event) catch unreachable;
    }

    fn windowSize(glfw_window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));

        window.height = @intCast(height);
        window.width = @intCast(width);

        const event = root.WindowEvent{
            .resize = .{
                .height = @intCast(height),
                .width = @intCast(width),

                .is_live = false,
            },
        };

        window.event_queue.push(event) catch unreachable;
    }

    fn windowClose(glfw_window: ?*c.GLFWwindow) callconv(.c) void {
        const window: *Window = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return));
        window.event_queue.push(.close) catch unreachable;
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

const Allocator = std.mem.Allocator;
