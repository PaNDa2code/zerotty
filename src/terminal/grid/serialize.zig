const std = @import("std");
const Grid = @import("Grid.zig");
const root = @import("../root.zig");

pub fn serialize(grid: *const Grid, writer: *std.Io.Writer) !void {
    try writeUsize(writer, grid.rows_width);
    try writeUsize(writer, grid.visable_rows);
    try writeUsize(writer, grid.max_scrollback);
    try writeUsize(writer, grid.scroll_offset);

    try writer.writeInt(u32, grid.bg_color.toInt(), .little);

    try writeUsize(writer, grid.cursor_x);
    try writeUsize(writer, grid.cursor_y);

    try writer.writeByte(@intFromBool(grid.wrap_pending));

    try writeUsize(writer, grid.rows.items.len);
    for (grid.rows.items) |row| {
        try writeUsize(writer, row.cells.len);
        try writer.writeSliceEndian(root.grid.Cell, row.cells, .little);
        try writer.writeByte(@intFromBool(row.wrapped));
    }
}

pub fn deserialize(grid: *Grid, allocator: std.mem.Allocator, reader: *std.Io.Reader) !void {
    // Start from an empty grid. The caller owns `grid` but may reuse it.
    for (grid.rows.items) |row| allocator.free(row.cells);
    grid.rows.clearRetainingCapacity();

    grid.rows_width = try readUsize(reader);
    grid.visable_rows = try readUsize(reader);
    grid.max_scrollback = try readUsize(reader);
    grid.scroll_offset = try readUsize(reader);

    grid.bg_color = .fromInt(try reader.takeInt(u32, .little));

    grid.cursor_x = try readUsize(reader);
    grid.cursor_y = try readUsize(reader);

    grid.wrap_pending = (try reader.takeByte()) != 0;

    const row_count = try readUsize(reader);

    errdefer {
        for (grid.rows.items) |row| allocator.free(row.cells);
        grid.rows.clearRetainingCapacity();
    }

    for (0..row_count) |_| {
        const cells_len = try readUsize(reader);
        if (cells_len != grid.rows_width) return error.InvalidGrid;

        const cells = try allocator.alloc(root.grid.Cell, cells_len);
        errdefer allocator.free(cells);
        try reader.readSliceEndian(root.grid.Cell, cells, .little);

        const wrapped = (try reader.takeByte()) != 0;
        try grid.rows.append(allocator, .{
            .cells = cells,
            .wrapped = wrapped,
        });
    }
}

fn writeUsize(writer: *std.Io.Writer, v: usize) !void {
    try writer.writeInt(u64, v, .little);
}

fn readUsize(reader: *std.Io.Reader) !usize {
    const v = try reader.takeInt(u64, .little);
    return std.math.cast(usize, v) orelse error.Overflow;
}
