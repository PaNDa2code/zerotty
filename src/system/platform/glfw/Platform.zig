const std = @import("std");

const Platform = @This();

pub const Window = @import("Window.zig");
const root = @import("zerotty").system.platform;

pub const Clipboard = struct {
    const c = @import("c_glfw");

    window: ?*c.GLFWwindow,

    pub fn getString(clip: Clipboard) []const u8 {
        const str_ptr = c.glfwGetClipboardString(clip.window);
        return std.mem.span(str_ptr);
    }

    pub fn setString(clip: Clipboard, str: [:0]const u8) void {
        c.glfwSetClipboardString(clip.window, str.ptr);
    }
};

allocator: std.mem.Allocator,

current_window: ?Window = null,
clipboard: Clipboard = undefined,

pub fn init(allocator: std.mem.Allocator) Platform {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Platform) void {
    if (self.current_window) |w|
        w.destroy(self.allocator);
}

pub fn createWindow(self: *Platform, options: root.WindowOptions) !void {
    const win = try Window.create(self.allocator, options);

    self.current_window = win;
    self.clipboard.window = @ptrCast(win.window);
}

pub fn getWindowNativeHandles(self: *Platform) !root.WindowNativeHandles {
    return .{ .window = (try self.getWindow()).window };
}

pub fn pollEvents(self: *Platform) !void {
    const w = try self.getWindow();
    w.poll();
}

pub fn eventQueue(self: *Platform) *root.EventQueue {
    return (self.getWindow() catch unreachable).event_queue;
}

fn getWindow(self: *Platform) !*Window {
    return if (self.current_window) |*w| w else error.WindowNotCreated;
}
