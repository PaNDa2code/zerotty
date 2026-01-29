pub const Api = @import("build_options").@"window-system";

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const comptime_check = build_options.comptime_check;

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
        display: *anyopaque,
    },
    .glfw => struct {
        window: *anyopaque,
    },
};

pub const OpenGLContextCreateInfo = struct {};
pub const GLESContextCreateInfo = struct {};

pub const InputHandleCallbackFn = fn (*InputContext, u32, bool, []u8) usize;

pub const ResizeEvent = struct {
    height: u32,
    width: u32,
    is_live: bool, // user is still resizing
};

pub const InputEvent = @import("input").InputEvent;

pub const WindowEvent = union(enum) {
    resize: ResizeEvent,
    input: InputEvent,
    focus: bool,
    expose: bool,
    close,
    none,
};

pub fn Queue(T: type, default: T, max_slots: comptime_int) type {
    return struct {
        const Self = @This();

        queue: [max_slots]T = [1]T{default} ** max_slots,
        len: usize = 0,

        pub const empty = Self{};

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.queue[self.len];
        }

        pub const PushError = error{
            QueueIsFull,
        };

        pub fn push(self: *Self, event: T) PushError!void {
            if (self.len == max_slots)
                return error.QueueIsFull;

            self.queue[self.len] = event;
            self.len += 1;
        }
    };
}

pub const EventQueue = Queue(WindowEvent, .none, MAX_EVENTS);

/// comptime polymorphism interface for window
fn WindowInterface(WindowBackend: type) type {
    return struct {
        const Self = @This();

        comptime {
            backendAssert(WindowBackend);
        }

        running: bool,
        w: WindowBackend,

        renderer_semaphore: std.Thread.Semaphore = .{},

        event_queue: EventQueue = .empty,

        pub fn initAlloc(allocator: std.mem.Allocator, options: WindowCreateOptions) !*Self {
            const window = try allocator.create(Self);
            window.* = Self.new(options.title, options.height, options.width);
            try window.open(allocator);
            return window;
        }

        pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
            self.close();
            allocator.destroy(self);
        }

        pub fn new(title: []const u8, window_height: u32, window_width: u32) Self {
            return .{
                .w = WindowBackend.new(title, window_height, window_width),
                .running = false,
            };
        }

        pub fn open(self: *Self, allocator: std.mem.Allocator) !void {
            try self.w.open(allocator);
        }

        pub fn setTitle(self: *Self, title: []const u8) !void {
            try self.w.setTitle(title);
        }

        pub fn poll(self: *Self) void {
            self.w.event_queue = &self.event_queue;
            self.w.poll();
        }

        pub fn close(self: *Self) void {
            self.w.close();
        }

        pub fn getHandles(self: *Self) WindowHandles {
            return self.w.getHandles();
        }

        pub fn height(self: *const Self) u32 {
            return self.w.height;
        }

        pub fn width(self: *const Self) u32 {
            return self.w.width;
        }

        pub fn nextEvent(self: *Self) ?WindowEvent {
            return self.event_queue.pop();
        }
    };
}

fn backendAssert(comptime T: type) void {
    comptime {
        const decls = [_][]const u8{
            "new",
            "open",
            "close",
            "poll",
            "setTitle",
            "getHandles",
        };

        for (decls) |decl| {
            if (!@hasDecl(T, decl))
                @compileError("Window backend " ++ @typeName(T) ++ " must declare " ++ decl);
        }

        const fields = [_][]const u8{
            "width",
            "height",
            "event_queue",
        };

        for (fields) |field| {
            if (!@hasField(T, field))
                @compileError("Window backend " ++ @typeName(T) ++ " must have " ++ field ++ " field");
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

pub const InputContext = switch (Api) {
    .xlib, .xcb => @import("input").Xkb,
    else => void,
};

const MAX_EVENTS = 500;

pub const Window = WindowInterface(Backend);

const test_alloc = std.testing.allocator;

comptime {
    if (comptime_check) {
        _ = WindowInterface(Win32);
        _ = WindowInterface(Xlib);
        _ = WindowInterface(Xcb);
        _ = WindowInterface(GLFW);
    }
}
