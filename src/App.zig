const App = @This();

allocator: std.mem.Allocator,

window: *win.Window,
renderer: Renderer,
io_event_loop: io.EventLoop,

buf: []u8,
terminal: Terminal,

pub fn init(allocator: std.mem.Allocator) !App {
    const window = try win.Window.initAlloc(allocator, .{
        .title = "zerotty",
        .height = 600,
        .width = 800,
    });

    const renderer = try Renderer.init(allocator, window.getHandles(), .{
        .surface_width = window.w.width,
        .surface_height = window.w.height,
        .grid_rows = 100,
        .grid_cols = 100,
    });

    var io_event_loop = try io.EventLoop.init(allocator, 20);

    const terminal = try Terminal.init(allocator, .{
        .shell_path = "/bin/bash",
        .rows = 100,
        .cols = 100,
    });

    const buf = try allocator.alloc(u8, 1024);
    const master = std.fs.File{ .handle = terminal.pty.master };
    try io_event_loop.read(master, buf, readPty, null);

    return .{
        .allocator = allocator,
        .window = window,
        .renderer = renderer,
        .io_event_loop = io_event_loop,

        .buf = buf,
        .terminal = terminal,
    };
}

pub fn run(self: *App) !void {
    const thread = try std.Thread.spawn(.{}, renderLoop, .{
        &self.renderer,
        &self.window.running,
    });
    defer thread.detach();

    while (self.window.running) {
        self.window.poll();
    }
}

pub fn deinit(self: *App) void {
    self.renderer.deinit();
    self.window.destroy(self.allocator);
    self.io_event_loop.deinit(self.allocator);
    self.terminal.deinit(self.allocator);
}

fn readPty(event: *io.EventLoop.Event, len: usize, _: ?*anyopaque) io.EventLoop.CallbackAction {
    std.log.debug("pty => {s}", .{event.request.op_data.read[0..len]});
    return .retry;
}

fn renderLoop(renderer: *Renderer, running: *bool) !void {
    while (running.*) {
        try renderer.renaderGrid();
    }
}

const std = @import("std");
const io = @import("io");
const win = @import("window");
const Terminal = @import("Terminal.zig");
const Renderer = @import("Renderer");
