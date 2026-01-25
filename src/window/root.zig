pub const Api = @import("build_options").@"window-system";

fn WindowInterface(WindowType: type) type {
    return struct {
        const Self = @This();

        window: WindowType,

        pub fn initAlloc(allocator: std.mem.Allocator, title: []const u8, height: u32, width: u32) !*Self {
            var window = try allocator.create(WindowType);
            window.* = WindowType.new(title, height, width);
            window.setup(allocator);
            return window;
        }

        pub fn new(title: []const u8, height: u32, width: u32) Self {
            return .{
                .window = WindowType.new(title, height, width),
            };
        }

        pub fn open(self: *Self, allocator: std.mem.Allocator) !void {
            try self.window.open(allocator);
        }

        pub fn setTitle(self: *Self, title: []const u8) !void {
            try self.window.setTitle(title);
        }

        pub fn pumpMessages(self: *Self) void {
            self.window.pumpMessages();
        }

        pub fn close(self: *Self) void {
            self.window.close();
        }
    };
}

pub const RenderCreateInfo = struct {
    handles: WindowHandles,
    width: u32,
    hieght: u32,
};

pub const WindowHandles = switch (Api) {
    .win32 => struct {
        hwnd: *anyopaque,
        hinstance: *anyopaque,
    },
    .xcb => struct {
        connection: *anyopaque,
        window: u32,
    },
    .xlib => struct {
        window: c_ulong,
        dpy: *anyopaque,
    },
    .glfw => struct {
        window: *anyopaque,
    },
};


pub const OpenGLContextCreateInfo = struct {};

const Impl = switch (Api) {
    .win32 => @import("Win32.zig"),
    .xlib => @import("Xlib.zig"),
    .xcb => @import("Xcb.zig"),
    .glfw => @import("GLFW.zig"),
};

pub const Window = Impl;

const std = @import("std");
