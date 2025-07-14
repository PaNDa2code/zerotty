const CellProgram = @This();

pub const Cell = packed struct {
    row: u32, // location 1
    col: u32, // location 2
    char: u32, // location 3
    fg_color: ColorRGBA, // location 4
    bg_color: ColorRGBA, // location 5
};

const test_cell = Cell;

data: []Cell,
rows: u32,
columns: u32,

pub const CellProgramOptions = struct {
    cell_height: usize,
    cell_width: usize,
    screen_height: usize,
    screen_width: usize,
};

pub fn create(allocator: Allocator, options: CellProgramOptions) !CellProgram {
    const rows = options.screen_height / options.cell_height;
    const columns = options.screen_width / options.cell_width;

    const data = try allocator.alloc(Cell, rows * columns);

    @memset(data, .{
        .row = 0,
        .col = 0,
        .char = 'a',
        .fg_color = .White,
        .bg_color = .Gray,
    });

    for (data, 0..) |*cell, i| {
        cell.char = @intCast('a' + (i % 26));
        cell.row = @intCast(i / columns);
        cell.col = @intCast(i % columns);
    }

    return .{
        .data = data,
        .rows = @intCast(rows),
        .columns = @intCast(columns),
    };
}

pub fn resize(self: *CellProgram, allocator: Allocator, options: CellProgramOptions) !void {
    const rows = options.screen_height / options.cell_height;
    const columns = options.screen_width / options.cell_width;

    const data = try allocator.alloc(Cell, rows * columns);

    @memset(data, .{
        .row = 0,
        .col = 0,
        .char = 'a',
        .fg_color = .White,
        .bg_color = .Gray,
    });

    for (data, 0..) |*cell, i| {
        cell.char = @intCast('a' + (i % 26));
        cell.row = @intCast(i / columns);
        cell.col = @intCast(i % columns);
    }

    allocator.free(self.data);

    self.* = .{
        .data = data,
        .rows = @intCast(rows),
        .columns = @intCast(columns),
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const ColorRGBA = common.ColorRGBA;
