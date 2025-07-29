window: Window,
pty: Pty,
buffer: CircularBuffer,
child: ChildProcess,
vt_parser: VTParser,
allocator: Allocator,

const App = @This();

pub fn new(allocator: Allocator) App {
    return .{
        .window = Window.new("zerotty", 720, 1280),
        .allocator = allocator,
        .vt_parser = VTParser.init(vtParseCallback),
        .child = .{ .exe_path = if (@import("builtin").os.tag == .windows) "cmd" else "bash" },
        .pty = undefined,
        .buffer = undefined,
    };
}

pub fn start(self: *App) !void {
    var arina = std.heap.ArenaAllocator.init(self.allocator);
    defer arina.deinit();

    try self.window.open(self.allocator);
    try self.buffer.init(1024 * 64);
    try self.pty.open(.{});
    try self.child.start(arina.allocator(), &self.pty);
}

pub fn loop(self: *App) void {
    var buffer: [1024]u8 = undefined;
    const child_stdout = self.child.stdout.?;

    render = &self.window.renderer;
    _pty = &self.pty;

    const len = child_stdout.read(buffer[0..]) catch unreachable;
    self.vt_parser.parse(buffer[0..len]);

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

var render: *Renderer = undefined;
var _pty: *Pty = undefined;

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
    self.buffer.deinit();
    self.pty.close();
}

const Window = @import("window/root.zig").Window;
const Pty = @import("pty/root.zig").Pty;
const CircularBuffer = @import("CircularBuffer.zig");
const ChildProcess = @import("ChildProcess.zig");
const Renderer = @import("renderer/root.zig");
const FPS = @import("renderer/FPS.zig");
const VTParser = vtparse.VTParser;
const Allocator = std.mem.Allocator;

const std = @import("std");
const build_options = @import("build_options");
const vtparse = @import("vtparse");
