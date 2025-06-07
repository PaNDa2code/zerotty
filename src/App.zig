window: Window,
pty: Pty,
buffer: CircularBuffer,
child: ChildProcess,
vt_parser: VTParser,
allocator: Allocator,

const App = @This();

pub fn new(allocator: Allocator) App {
    return .{
        .window = Window.new("zterm", 600, 800),
        .allocator = allocator,
        .vt_parser = VTParser.init(vt_parse_callback),
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
    // var buffer: [1024]u8 = undefined;
    // const child_stdout = self.child.stdout.?;
    //
    // const len = child_stdout.read(buffer[0..]) catch unreachable;
    // self.vt_parser.parse(buffer[0..len]);

    while (!self.window.exit) {
        self.window.pumpMessages();
        self.window.renderer.clearBuffer(.Gray);
        self.window.renderer.renaderText("HelloWorld!", 10, 570, .White);
        self.window.renderer.renaderText("PaNDa2code", 10, 540, .Green);
        self.window.renderer.presentBuffer();
    }
}

fn vt_parse_callback(state: *const vtparse.ParserData, to_action: vtparse.Action, char: u8) void {
    std.log.info("{0s: <10}{1s: <13} => {2c} {2d}", .{ @tagName(state.state), @tagName(to_action), char });
}

pub fn exit(self: *App) void {
    self.window.close();
    self.child.terminate();
    self.buffer.deinit();
    self.pty.close();
}

const Window = @import("window.zig").Window;
const Pty = @import("pty.zig").Pty;
const CircularBuffer = @import("CircularBuffer.zig");
const ChildProcess = @import("ChildProcess.zig");
const VTParser = vtparse.VTParser;
const Allocator = std.mem.Allocator;

const std = @import("std");
const config = @import("config");
const vtparse = @import("vtparse");
