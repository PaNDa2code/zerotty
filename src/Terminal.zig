const Terminal = @This();

pty: Pty,
shell: ChildProcess,
grid: Grid,

pub const TerminalSettings = struct {
    shell_path: []const u8 = "",
    rows: u32,
    cols: u32,
};

pub fn init(allocator: std.mem.Allocator, settings: TerminalSettings) !Terminal {
    var pty: Pty = undefined;
    try pty.open(.{
        .shell = .bash,
        .async_io = true,
    });

    var shell = ChildProcess{
        .exe_path = settings.shell_path,
    };
    try shell.start(allocator, &pty);

    const grid = try Grid.init(allocator, .{
        .visable_columns = settings.cols,
        .visable_rows = settings.rows, 
    });

    return .{
        .pty = pty,
        .shell = shell,
        .grid = grid,
    };
}

pub fn deinit(self: *Terminal, _: std.mem.Allocator) void {
    self.pty.close();
    self.shell.terminate();
    self.grid.deinit();
}

const std = @import("std");
const Pty = @import("pty").Pty;
const ChildProcess = @import("ChildProcess");
const Scrollback = @import("Scrollback.zig");
const Grid = @import("grid/root.zig").Grid;
