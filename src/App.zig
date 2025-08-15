window: Window,
pty: Pty,
buffer: CircularBuffer,
child: ChildProcess,
vt_parser: VTParser,
allocator: Allocator,

io_event_loop: EventLoop,

const App = @This();

pub fn new(allocator: Allocator) App {
    return .{
        .window = Window.new("zerotty", 720, 1280),
        .allocator = allocator,
        .vt_parser = VTParser.init(vtParseCallback),
        .child = if (@import("builtin").os.tag == .windows)
            .{ .exe_path = "cmd", .args = &.{ "cmd", "" } }
        else
            .{ .exe_path = "bash", .args = &.{ "bash", "--norc", "--noprofile" } },
        .pty = undefined,
        .buffer = undefined,
        .io_event_loop = undefined,
    };
}


var render: *Renderer = undefined;
var _pty: *Pty = undefined;

pub fn start(self: *App) !void {
    try self.window.open(self.allocator);
    try self.buffer.init(1024 * 64);
    try self.pty.open(.{});
    self.child.unsetEvnVar("PS0");
    try self.child.setEnvVar(self.allocator, "PS1", "\\h@\\u:\\w> ");
    try self.child.start(self.allocator, &self.pty);

    render = &self.window.renderer;
    _pty = &self.pty;

    self.io_event_loop = try .init();

    const master_file = try AysncFile.init(self.child.stdout.?.handle);

    const master_event = try master_file.asyncRead(self.allocator, self.buffer.buffer, &pty_read_callback, self);

    try self.io_event_loop.addEvent(self.allocator, master_event);
}

pub fn pty_read_callback(_: *const EventLoop.Event, buf: []u8, data: ?*anyopaque) void {
    std.log.info("pty_read_callback {}", .{buf.len});
    const app: *App = @alignCast(@ptrCast(data));
    app.vt_parser.parse(buf);
}

pub fn loop(self: *App) void {
    try self.io_event_loop.run();
    self.window.render_cb = &drawCallBack;
    self.window.resize_cb = &resizeCallBack;
    while (!self.window.exit) {
        self.window.pumpMessages();
    }
}

pub fn drawCallBack(renderer: *Renderer) void {
    renderer.clearBuffer(.Gray);
    renderer.renaderGrid();
    renderer.presentBuffer();
    std.io.getStdOut().writer().print("\rFPS = {d:.2}", .{renderer.getFps()}) catch unreachable;
}

pub fn resizeCallBack(_: u32, _: u32) void {
    _pty.resize(.{
        .width = @intCast(render.backend.grid.columns),
        .height = @intCast(render.backend.grid.rows),
    }) catch unreachable;
}

fn vtParseCallback(state: *const vtparse.ParserData, to_action: vtparse.Action, char: u8) void {
    switch (to_action) {
        .CSI_DISPATCH => {
            const params = state.params[0..@intCast(state.num_params)];
            if (char == 'q' and state.num_intermediate_chars == 1 and state.intermediate_chars[0] == ' ') {
                const cursor_style_code = params[0];
                std.log.info("cursor_style_code = {}", .{cursor_style_code});
            }
        },
        .PRINT, .OSC_PUT => {
            render.setCursorCell(char) catch undefined;
        },
        else => {
            std.log.info("{0s: <10}{1s: <13} => {2c} {2d}", .{ @tagName(state.state), @tagName(to_action), char });
        },
    }
}

pub fn exit(self: *App) void {
    self.window.close();
    self.child.terminate();
    self.child.deinit();
    self.buffer.deinit();
    self.pty.close();
}

const Window = @import("window/root.zig").Window;
const Pty = @import("pty/root.zig").Pty;
const CircularBuffer = @import("CircularBuffer.zig");
const ChildProcess = @import("ChildProcess.zig");
const Renderer = @import("renderer/root.zig");
const FPS = @import("renderer/FPS.zig");
const AysncFile = @import("io/File.zig");
const EventLoop = @import("io/EventLoop.zig");
const VTParser = vtparse.VTParser;
const Allocator = std.mem.Allocator;

const std = @import("std");
const build_options = @import("build_options");
const vtparse = @import("vtparse");
