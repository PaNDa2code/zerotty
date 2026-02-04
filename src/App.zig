const App = @This();

allocator: std.mem.Allocator,

window: *win.Window,
renderer: Renderer,
io_event_loop: io.EventLoop,

buf: []u8,
terminal: *Terminal,

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

    const terminal = try allocator.create(Terminal);

    terminal.* = try Terminal.init(allocator, if (os_tag == .linux) .{
        .shell_path = "/bin/bash",
        .shell_args = &.{ "bash", "--norc", "--noprofile" },
        .rows = 100,
        .cols = 100,
    } else if (os_tag == .windows) .{
        .shell_path = "cmd.exe",
        .shell_args = &.{"cmd"},
        .rows = 100,
        .cols = 100,
    });

    const buf = try allocator.alloc(u8, 1024);
    try io_event_loop.read(terminal.shell.stdout.?, buf, ptyReadCallback, terminal);

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
    self.terminal.vtparser.user_data = self.terminal;

    var running = true;

    while (running) {
        self.window.poll();
        try self.io_event_loop.poll(0);

        while (self.window.nextEvent()) |event| {
            std.log.debug("event: {any}", .{event});
            if (event == .close) {
                running = false;
                break;
            }
        }

        try self.renderer.beginFrame();

        try self.renderer.setViewport(
            0,
            0,
            self.window.width(),
            self.window.height(),
        );

        self.renderer.clear(.black);
        try self.renderer.endFrame();
        try self.renderer.presnt();
    }
}

pub fn deinit(self: *App) void {
    self.renderer.deinit();
    self.window.destroy(self.allocator);
    self.io_event_loop.deinit(self.allocator);
    self.terminal.deinit(self.allocator);
    self.allocator.free(self.buf);

    self.allocator.destroy(self.terminal);
}

fn ptyReadCallback(event: *io.EventLoop.Event, len: usize, user_data: ?*anyopaque) io.EventLoop.CallbackAction {
    const buffer = event.request.op_data.read[0..len];
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));
    terminal.vtparser.parse(buffer);
    return .retry;
}

const std = @import("std");
const builtin = @import("builtin");
const io = @import("io");
const win = @import("window");
const Terminal = @import("Terminal.zig");
const Renderer = @import("renderer").Renderer;

const os_tag = builtin.os.tag;
