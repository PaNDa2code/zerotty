const input = @import("../input/root.zig");

const platform = @import("build_options").@"window-system";

pub const WindowNativeHandles = switch (platform) {
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

pub const Platform = switch (platform) {
    .glfw => @import("glfw/Platform.zig"),
    .xcb, .xlib => @import("linux/Platform.zig"),
    .win32 => @import("win32/Platform.zig"),
};

pub const WindowRendererRequirements = struct {
    color_bits: u8 = 32,
    depth_bits: u8 = 24,
    stencil_bits: u8 = 8,
    alpha_bits: u8 = 8,
    double_buffer: bool = true,
    samples: u8 = 0,
};

pub const WindowOptions = struct {
    height: u32,
    width: u32,
    title: []const u8,
    renderer_requirements: WindowRendererRequirements = .{},
};

pub const ResizeEvent = struct {
    height: u32,
    width: u32,
    is_live: bool = false,
};

pub const Event = union(enum) {
    none,
    close,

    input: input.InputEvent,
    resize: ResizeEvent,

    focus: bool,
    expose: bool,
};

const BoundedQueue = @import("zerotty").ds.queue.BoundedQueue;

pub const EventQueue = BoundedQueue(Event, .none, 256);
