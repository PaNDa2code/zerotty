const App = @This();

allocator: std.mem.Allocator,

window: *win.Window,
io_event_loop: io.EventLoop,

terminal: Terminal,

pub fn init(allocator: std.mem.Allocator) !App {
    const window = try win.Window.initAlloc(allocator, .{
        .title = "zerotty",
        .height = 600,
        .width = 800,
    });

    const io_event_loop = try io.EventLoop.init(allocator, 20);

    const terminal = try Terminal.init(allocator, .{
        .shell_path = "/bin/bash",
        .rows = 100,
        .cols = 100,
    });

    return .{
        .allocator = allocator,
        .window = window,
        .io_event_loop = io_event_loop,

        .terminal = terminal,
    };
}

pub fn run(self: *App) !void {
    while (self.window.running) {
        self.window.poll();
    }
}

pub fn deinit(self: *App) void {
    self.window.destroy(self.allocator);
    self.io_event_loop.deinit(self.allocator);
    self.terminal.deinit(self.allocator);
}

const std = @import("std");
const io = @import("io");
const win = @import("window");
const Terminal = @import("Terminal.zig");
