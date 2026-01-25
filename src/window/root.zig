pub const Api = @import("build_options").@"window-system";

const std = @import("std");

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

/// comptime polymorphism interface for window
fn WindowInterface(WindowBackend: type) type {
    return struct {
        const Self = @This();

        comptime {
            backendAssert(WindowBackend);
        }

        // pub const InputContext = void;
        // pub const InputCallbackFn = fn (*InputContext, u21, bool) void;

        w: WindowBackend,
        // input_ctx: InputContext,

        pub fn initAlloc(allocator: std.mem.Allocator, options: WindowCreateOptions) !*Self {
            const window = try allocator.create(Self);
            window.* = WindowBackend.new(options.title, options.height, options.width);
            window.open(allocator);
            return window;
        }

        pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
            self.close();
            allocator.destroy(self);
        }

        pub fn new(title: []const u8, height: u32, width: u32) Self {
            return .{
                .w = WindowBackend.new(title, height, width),
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

fn backendAssert(comptime T: type) void {
    comptime {
        const decls = [_][]const u8{
            "new",
            "open",
            "close",
            "pumpMessages",
            "setTitle",
        };

        for (decls) |decl| {
            if (!@hasDecl(T, decl))
                @compileError("Backend " ++ @typeName(T) ++ " must declare " ++ decl);
        }

        const fields = [_][]const u8{
            "width",
            "height",
        };

        for (fields) |field| {
            if (!@hasField(T, field))
                @compileError("Backend must have " ++ field ++ " field");
        }
    }
}

const Win32 = @import("Win32.zig");
const Xlib = @import("Xlib.zig");
const Xcb = @import("Xcb.zig");
const GLFW = @import("GLFW.zig");

const Backend = switch (Api) {
    .win32 => Win32,
    .xlib => Xlib,
    .xcb => Xcb,
    .glfw => GLFW,
};

pub const Window = Backend;

comptime {
    _ = WindowInterface(Win32);
    _ = WindowInterface(Xlib);
    _ = WindowInterface(Xcb);
    _ = WindowInterface(GLFW);
}

// const test_alloc = std.testing.allocator;
//
// test Win32 {
//     const window = try WindowInterface(Win32).initAlloc(test_alloc);
//     defer window.destroy(test_alloc);
// }
//
// test Xcb {
//     const window = try WindowInterface(Xcb).initAlloc(test_alloc);
//     defer window.destroy(test_alloc);
// }
//
// test Xlib {
//     const window = try WindowInterface(Xlib).initAlloc(test_alloc);
//     defer window.destroy(test_alloc);
// }
//
// test GLFW {
//     const window = try WindowInterface(GLFW).initAlloc(test_alloc);
//     defer window.destroy(test_alloc);
// }
