//! TODO: optimize memory layout and preformance

const std = @import("std");
const Grid = @This();
const Row = @import("Row.zig");
const grid = @import("root.zig");
const Cell = grid.Cell;

rows: std.ArrayList(Row) = .empty,
visable_rows: usize,
rows_width: usize,
scroll_offset: usize = 0,

cursor_x: usize = 0,
cursor_y: usize = 0,

/// Resize the visible viewport. Existing rows are re-widthed in place
/// (padded when growing, truncated when shrinking) and new blank rows
/// are appended if there aren't enough tracked rows yet to fill the
/// viewport. Scrollback (rows beyond `visable_rows`) is left intact.
pub fn resizeVisable(
    self: *Grid,
    allocator: std.mem.Allocator,
    visable_rows: usize,
    rows_width: usize,
) !void {
    if (self.visable_rows == visable_rows and self.rows_width == rows_width)
        return;

    if (rows_width != self.rows_width) {
        for (self.rows.items) |*row| {
            if (rows_width > self.rows_width) {
                const pad_count = rows_width - row.len();
                const blanks = try allocator.alloc(Cell, pad_count);
                defer allocator.free(blanks);
                @memset(blanks, .default);
                try row.extend(allocator, blanks);
            } else if (row.len() > rows_width) {
                // Truncated cells are simply dropped here. A fuller
                // implementation would push these into a wrapped
                // continuation row instead of discarding them.
                const dropped = try row.shrink(allocator, rows_width);
                allocator.free(dropped);
            }
        }
        self.rows_width = rows_width;
    }

    // Ensure we have enough rows to fill the new viewport height.
    if (self.rows.items.len < visable_rows) {
        const needed = visable_rows - self.rows.items.len;
        var i: usize = 0;
        while (i < needed) : (i += 1) {
            var new_row = Row{};
            const blanks = try allocator.alloc(Cell, self.rows_width);
            defer allocator.free(blanks);
            @memset(blanks, .default);
            try new_row.extend(allocator, blanks);
            try self.appendLiveRow(allocator, new_row);
        }
    }

    self.visable_rows = visable_rows;
    self.clampScrollOffset();

    if (self.rows_width > 0 and self.cursor_x >= self.rows_width) {
        self.cursor_x = self.rows_width - 1;
    }
    if (self.visable_rows > 0 and self.cursor_y >= self.visable_rows) {
        self.cursor_y = self.visable_rows - 1;
    }
}

/// How many rows back into history the viewport is currently allowed
/// to scroll (0 if there's no scrollback beyond the visible area).
pub fn maxScrollOffset(self: *const Grid) usize {
    if (self.rows.items.len <= self.visable_rows) return 0;
    return self.rows.items.len - self.visable_rows;
}

fn clampScrollOffset(self: *Grid) void {
    const max = self.maxScrollOffset();
    if (self.scroll_offset > max) self.scroll_offset = max;
}

/// Append a row to the live buffer, preserving the user's current
/// scrollback position instead of snapping the view to the bottom.
///
/// - If the user is scrolled back into history (`scroll_offset > 0`),
///   the offset grows by one alongside `maxScrollOffset`, so the same
///   historical content stays on screen.
/// - If the user is already pinned to the bottom (`scroll_offset == 0`),
///   it's left at 0, so the view keeps following the live output —
///   this is the "default scroll down" behavior for new rows.
fn appendLiveRow(self: *Grid, allocator: std.mem.Allocator, row: Row) !void {
    try self.rows.append(allocator, row);
    if (self.scroll_offset > 0) {
        self.scroll_offset += 1;
    }
}

/// Scroll the viewport up (towards older history) by `n` rows.
pub fn scrollUp(self: *Grid, n: usize) void {
    self.scroll_offset = @min(self.scroll_offset + n, self.maxScrollOffset());
}

/// Scroll the viewport down (towards the live output) by `n` rows.
pub fn scrollDown(self: *Grid, n: usize) void {
    self.scroll_offset -|= n;
}

/// Jump straight back to the live/bottom position.
pub fn scrollToBottom(self: *Grid) void {
    self.scroll_offset = 0;
}

/// Slice of rows currently visible given the scroll offset.
pub fn visibleRows(self: *const Grid) []Row {
    if (self.rows.items.len == 0) return &.{};

    const max_offset = self.maxScrollOffset();
    const offset = @min(self.scroll_offset, max_offset);
    const top = max_offset - offset;
    const bottom = @min(top + self.visable_rows, self.rows.items.len);
    return self.rows.items[top..bottom];
}

/// Ensure there are at least `visable_rows` rows in the buffer,
/// appending blank ones if not. Safe to call unconditionally.
fn ensureLiveRows(self: *Grid, allocator: std.mem.Allocator) !void {
    while (self.rows.items.len < self.visable_rows) {
        var new_row = Row{};
        const blanks = try allocator.alloc(Cell, self.rows_width);
        defer allocator.free(blanks);
        @memset(blanks, .default);
        try new_row.extend(allocator, blanks);
        try self.appendLiveRow(allocator, new_row);
    }
}

/// Index into `rows` that corresponds to the current cursor_y,
/// always relative to the live (unscrolled) bottom of the buffer.
fn currentRowIndex(self: *const Grid) usize {
    return self.rows.items.len - self.visable_rows + self.cursor_y;
}

/// Write a cell at the cursor position and advance the cursor,
/// wrapping to the next line if we hit the right edge.
pub fn putChar(self: *Grid, allocator: std.mem.Allocator, cell: Cell) !void {
    try self.ensureLiveRows(allocator);

    const row = &self.rows.items[self.currentRowIndex()];
    if (self.cursor_x >= row.len()) {
        const pad_count = self.cursor_x - row.len() + 1;
        const pad = try allocator.alloc(Cell, pad_count);
        defer allocator.free(pad);
        @memset(pad, .default);
        try row.extend(allocator, pad);
    }
    row.backing_storage.items[self.cursor_x] = cell;

    self.cursor_x += 1;
    if (self.cursor_x >= self.rows_width) {
        try self.linefeed(allocator);
        self.cursor_x = 0;
    }
}

/// Move the cursor down one line, scrolling the live area
/// (appending a fresh blank row) if we're already at the bottom.
pub fn linefeed(self: *Grid, allocator: std.mem.Allocator) !void {
    try self.ensureLiveRows(allocator);

    self.cursor_y += 1;
    if (self.cursor_y >= self.visable_rows) {
        self.cursor_y = self.visable_rows - 1;

        var new_row = Row{};
        const blanks = try allocator.alloc(Cell, self.rows_width);
        defer allocator.free(blanks);
        @memset(blanks, .default);
        try new_row.extend(allocator, blanks);
        try self.appendLiveRow(allocator, new_row);
    }
}

/// Move cursor to column 0 of the current line.
pub fn carriageReturn(self: *Grid) void {
    self.cursor_x = 0;
}

pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
    for (self.rows.items) |*row| {
        row.backing_storage.deinit(allocator);
    }
    self.rows.deinit(allocator);
}

pub const Iterator = struct {
    grid: *const Grid,
    current_x: usize = 0,
    current_y: usize = 0,

    pub const Item = struct {
        x: usize,
        y: usize,
        cell: Cell,
    };

    pub fn next(self: *Iterator) ?Item {
        if (self.current_y >= self.grid.visable_rows) return null;

        const x = self.current_x;
        const y = self.current_y;
        var cell: Cell = .{
            .unicode = 0,
            .bg_color = .black,
            .fg_color = .white,
            .flags = .{},
        };

        const visible = self.grid.visibleRows();
        if (y < visible.len) {
            const row = &visible[y];
            if (x < row.len()) {
                cell = row.backing_storage.items[x];
            }
        }

        self.current_x += 1;
        if (self.current_x >= self.grid.rows_width) {
            self.current_x = 0;
            self.current_y += 1;
        }

        return .{ .x = x, .y = y, .cell = cell };
    }
};

pub fn iterator(self: *const Grid) Iterator {
    return .{ .grid = self };
}

test "resizeVisable clamps cursor_y and cursor_x" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 10,
        .rows_width = 10,
    };
    defer my_grid.deinit(allocator);

    my_grid.cursor_x = 8;
    my_grid.cursor_y = 8;

    // Resize viewport to smaller dimensions
    try my_grid.resizeVisable(allocator, 5, 5);

    try std.testing.expect(my_grid.cursor_x == 4);
    try std.testing.expect(my_grid.cursor_y == 4);
}
