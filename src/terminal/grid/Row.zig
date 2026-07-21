const std = @import("std");
const grid = @import("root.zig");
const Cell = grid.Cell;
const Row = @This();

backing_storage: std.ArrayList(Cell) = .empty,
wrapped: bool = false,

pub fn extend(self: *Row, allocator: std.mem.Allocator, cells: []const Cell) !void {
    try self.backing_storage.appendSlice(allocator, cells);
}

/// Shrinks the row to `new_len` cells, returning the cells that were
/// removed from the tail. Caller owns the returned slice.
pub fn shrink(self: *Row, allocator: std.mem.Allocator, new_len: usize) ![]const Cell {
    std.debug.assert(self.backing_storage.items.len >= new_len);
    const removed_count = self.backing_storage.items.len - new_len;
    if (removed_count == 0) return &.{};

    const removed_cells = try allocator.alloc(Cell, removed_count);
    @memcpy(removed_cells, self.backing_storage.items[new_len..]);
    self.backing_storage.shrinkRetainingCapacity(new_len);
    return removed_cells;
}

pub fn len(self: *const Row) usize {
    return self.backing_storage.items.len;
}
