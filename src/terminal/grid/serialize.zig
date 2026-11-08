const std = @import("std");
const Grid = @import("Grid.zig");
const root = @import("../root.zig");

pub fn serialize(grid: *const Grid, writer: *std.Io.Writer) !void {
    try writeUsize(writer, grid.cells.len);
    try writer.writeSliceEndian(root.grid.Cell, grid.cells, .little);

    try writeUsize(writer, grid.wrapped.len);
    for (grid.wrapped) |b| try writer.writeByte(@intFromBool(b));

    try writeUsize(writer, grid.cap_rows);
    try writeUsize(writer, grid.head);
    try writeUsize(writer, grid.row_count);
    try writeUsize(writer, grid.visable_rows);
    try writeUsize(writer, grid.rows_width);
    try writeUsize(writer, grid.max_scrollback);
    try writeUsize(writer, grid.scroll_offset);

    try writer.writeInt(u32, grid.bg_color.toInt(), .little);

    try writeUsize(writer, grid.cursor_x);
    try writeUsize(writer, grid.cursor_y);

    try writer.writeByte(@intFromBool(grid.wrap_pending));
}

pub fn deserialize(grid: *Grid, allocator: std.mem.Allocator, reader: *std.Io.Reader) !void {
    const cells_len = try readUsize(reader);
    grid.cells = try allocator.realloc(grid.cells, cells_len);
    try reader.readSliceEndian(root.grid.Cell, grid.cells, .little);

    const wrapped_len = try readUsize(reader);
    grid.wrapped = try allocator.realloc(grid.wrapped, wrapped_len);
    for (grid.wrapped) |*b| b.* = (try reader.takeByte()) != 0;

    grid.cap_rows = try readUsize(reader);
    grid.head = try readUsize(reader);
    grid.row_count = try readUsize(reader);
    grid.visable_rows = try readUsize(reader);
    grid.rows_width = try readUsize(reader);
    grid.max_scrollback = try readUsize(reader);
    grid.scroll_offset = try readUsize(reader);

    grid.bg_color = .fromInt(try reader.takeInt(u32, .little));

    grid.cursor_x = try readUsize(reader);
    grid.cursor_y = try readUsize(reader);

    grid.wrap_pending = (try reader.takeByte()) != 0;
}

fn writeUsize(writer: *std.Io.Writer, v: usize) !void {
    try writer.writeInt(u64, v, .little);
}

fn readUsize(reader: *std.Io.Reader) !usize {
    const v = try reader.takeInt(u64, .little);
    return std.math.cast(usize, v) orelse error.Overflow;
}
