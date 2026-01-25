pub const Api = @import("build_options").@"window-system";

fn WindowInterface(WinType: type) type {
    return struct {
        const Self = @This();

        comptime {
            backendAssert(WinType);
        }

        w: WinType,

        pub fn initAlloc(allocator: std.mem.Allocator, options: WindowCreateOptions) !*Self {
            const window = try allocator.create(Self);
            window.* = WinType.new(options.title, options.height, options.width);
            window.open(allocator);
            return window;
        }

        pub fn new(title: []const u8, height: u32, width: u32) Self {
            return .{
                .w = WinType.new(title, height, width),
            };
        }

        pub fn open(self: *Self, allocator: std.mem.Allocator) !void {
            try self.w.open(allocator);
        }

        pub fn setTitle(self: *Self, title: []const u8) !void {
            try self.w.setTitle(title);
        }

        pub fn pumpMessages(self: *Self) void {
            self.w.pumpMessages();
        }

        pub fn close(self: *Self) void {
            self.w.close();
        }
    };
}

pub const WindowCreateOptions = struct {
    title: []const u8 = "zerotty",
    height: u32,
    width: u32,
};

pub const RenderCreateInfo = struct {
    handles: WindowHandles,
    extent: Extent,
};

pub const Extent = struct {
    width: u32,
    height: u32,
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
pub const GLESContextCreateInfo = struct {};

const Win = switch (Api) {
    .win32 => @import("Win32.zig"),
    .xlib => @import("Xlib.zig"),
    .xcb => @import("Xcb.zig"),
    .glfw => @import("GLFW.zig"),
};

pub const Window = Win;

const std = @import("std");

fn backendAssert(comptime T: type) void {
    comptime {
        const methods = [_][]const u8{
            "new",
            "open",
            "close",
            "pumpMessages",
            "setTitle",
        };

        for (methods) |method| {
            if (!@hasDecl(T, method)) @compileError("Backend must define " ++ method);
        }
    }
}
