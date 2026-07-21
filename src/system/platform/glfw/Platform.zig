const std = @import("std");

const Platform = @This();

pub const Window = @import("Window.zig");
const root = @import("zerotty").system.platform;

allocator: std.mem.Allocator,

current_window: ?*Window = null,

event_queue: ?*root.EventQueue = null,

pub fn init(allocator: std.mem.Allocator) Platform {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Platform) void {
    if (self.current_window) |w|
        self.allocator.destroy(w);

    if (self.event_queue) |q|
        self.allocator.destroy(q);
}

pub fn createWindow(self: *Platform, options: root.WindowOptions) !void {
    const win = try self.allocator.create(Window);

    win.* = .new(options.title, options.height, options.width);

    self.current_window = win;

    const event_queue = try self.allocator.create(root.EventQueue);
    event_queue.* = .empty;

    self.event_queue = event_queue;

    try win.open(self.allocator, event_queue);
}

pub fn getWindowNativeHandles(self: *Platform) !root.WindowNativeHandles {
    return .{ .window = (try self.getWindow()).window };
}

pub fn pollEvents(self: *const Platform) !void {
    const w = try self.getWindow();
    w.poll();
}

pub fn eventQueue(self: *const Platform) *root.EventQueue {
    return self.event_queue orelse unreachable;
}

fn getWindow(self: *const Platform) !*Window {
    return self.current_window orelse error.WindowNotCreated;
}
