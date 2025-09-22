window: Window,
pty: Pty,
buffer: CircularBuffer,
child: ChildProcess,
vt_parser: VTParser,
allocator: Allocator,

io_event_loop: zerio.EventLoop,

const App = @This();

const log = std.log.scoped(.App);

pub fn new(allocator: Allocator) App {
    return .{
        .window = Window.new("zerotty", 720, 1280),
        .allocator = allocator,
        .vt_parser = VTParser.init(vtParseCallback, null),
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
var evloop: *zerio.EventLoop = undefined;
var child_stdin: std.fs.File = undefined;

pub fn start(self: *App) !void {
    try self.window.open(self.allocator);
    try self.buffer.init(1024 * 64);
    try self.pty.open(.{
        .size = .{
            .height = 0, // @intCast(self.window.renderer.backend.grid.rows),
            .width = 0, // @intCast(self.window.renderer.backend.grid.cols),
        },
    });

    // self.child.unsetEvnVar("PS0");
    // try self.child.setEnvVar(self.allocator, "PS1", "\\h@\\u:\\w> ");
    try self.child.start(self.allocator, &self.pty);

    render = &self.window.renderer;
    _pty = &self.pty;
    evloop = &self.io_event_loop;

    self.io_event_loop = try zerio.EventLoop.init(self.allocator, 8);

    try self.io_event_loop.read(self.child.stdout.?, self.buffer.buffer, &pty_read_callback, self);

    child_stdin = self.child.stdin.?;
}

pub fn pty_read_callback(ev: *const zerio.EventLoop.Event, n: usize, data: ?*anyopaque) zerio.EventLoop.CallbackAction {
    const buf = ev.request.op_data.read[0..n];
    const app: *App = @ptrCast(@alignCast(data));
    app.vt_parser.parse(buf);
    return .retry;
}

fn keyboard_cb(utf32: u32, press: bool) void {
    var utf8: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(@intCast(utf32), utf8[0..]) catch unreachable;
    log.debug("key pressed = {s} - 0x{x:04}", .{ utf8[0..@intCast(n)], utf32 });
    if (press)
        child_stdin.writeAll(utf8[0..n]) catch unreachable;
}

pub fn loop(self: *App) void {
    self.window.render_cb = &drawCallBack;
    self.window.resize_cb = &resizeCallBack;
    self.window.keyboard_cb = &keyboard_cb;
    while (!self.window.exit) {
        self.window.pumpMessages();
    }
}

pub fn drawCallBack(renderer: *Renderer) void {
    evloop.poll() catch unreachable;
    renderer.clearBuffer(.Black);
    renderer.renaderGrid();
    renderer.presentBuffer();
}

pub fn resizeCallBack(w: u32, h: u32) void {
    render.resize(w, h) catch unreachable;
    _pty.resize(.{
        .width = @intCast(render.backend.grid.cols),
        .height = @intCast(render.backend.grid.rows),
    }) catch unreachable;
}

// https://gist.github.com/ConnerWill/d4b6c776b509add763e17f9f113fd25b
fn vtParseCallback(state: *const vtparse.ParserData, to_action: vtparse.Action, char: u8) void {
    switch (to_action) {
        .CSI_DISPATCH => {
            const params = state.params[0..@intCast(state.num_params)];
            switch (char) {
                'H', 'f' => {
                    const row = if (params.len > 0 and params[0] != 0) params[0] else 1;
                    const col = if (params.len > 1 and params[1] != 0) params[1] else 1;

                    render.cursor.setPos(row - 1, col - 1);
                },
                'A' => {
                    const up_lines = params[0];
                    render.cursor.row += up_lines;
                },
                'B' => {
                    const down_lines = params[0];
                    render.cursor.row -= down_lines;
                },
                'C' => {
                    const right_lines = params[0];
                    render.cursor.col += right_lines;
                },
                'D' => {
                    const left_lines = params[0];
                    render.cursor.col -= left_lines;
                },
                'E' => {
                    const lines_down = params[0];
                    render.cursor.col = 0;
                    render.cursor.row += lines_down;
                },
                'F' => {
                    const lines_up = params[0];
                    render.cursor.col = 0;
                    render.cursor.row -= lines_up;
                },
                'G' => {
                    const col = params[0];
                    render.cursor.col = col;
                },
                'M' => {
                    render.cursor.row -= 1;
                },
                'J' => {
                    // TODO: erase display
                },
                else => {
                    // std.log.err("unhandled CSI_DISPATCH => {c}", .{char});
                },
            }
        },
        .PRINT, .EXECUTE => {
            switch (char) {
                '\r' => {
                    render.cursor.col = 0;
                },
                '\n' => {
                    render.cursor.row += 1;
                },
                else => {
                    render.setCursorCell(char) catch unreachable;
                },
            }
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
    self.io_event_loop.deinit(self.allocator);
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
const zerio = @import("zerio");
