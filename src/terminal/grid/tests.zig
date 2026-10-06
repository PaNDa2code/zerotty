const std = @import("std");
const grid = @import("root.zig");
const Grid = grid.Grid;
const Row = grid.Row;
const Cell = grid.Cell;
const RGBA = @import("zerotty").terminal.color.RGBA;

/// Cells of viewport row `y`. `Row` is only a view into the grid's storage, so
/// it must be fetched again after every mutation or resize.
fn rowCells(g: *const Grid, y: usize) []const Cell {
    return g.visibleRow(y).?.cells;
}

test "Grid Basic Writing and Cursor Movements" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 4,
        .rows_width = 5,
    };
    defer my_grid.deinit(allocator);

    // Initial state
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_y);

    const cell_a = Cell{ .unicode = 'A', .fg_color = .white, .bg_color = .black, .flags = .{} };
    const cell_b = Cell{ .unicode = 'B', .fg_color = .white, .bg_color = .black, .flags = .{} };

    // Write a character
    try my_grid.putChar(allocator, cell_a);
    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_y);

    // Write another
    try my_grid.putChar(allocator, cell_b);
    try std.testing.expectEqual(@as(usize, 2), my_grid.cursor_x);

    // Verify cell content
    const visible = rowCells(&my_grid, 0);
    try std.testing.expectEqual(@as(u32, 'A'), visible[0].unicode);
    try std.testing.expectEqual(@as(u32, 'B'), visible[1].unicode);

    // Carriage Return
    my_grid.carriageReturn();
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_x);

    // Linefeed
    try my_grid.linefeed(allocator);
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_y);
}

test "Grid Auto-wrapping" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 3,
        .rows_width = 3,
    };
    defer my_grid.deinit(allocator);

    const cell = Cell{ .unicode = 'X', .fg_color = .white, .bg_color = .black, .flags = .{} };

    // Write 3 characters to fill the line
    try my_grid.putChar(allocator, cell);
    try my_grid.putChar(allocator, cell);
    try my_grid.putChar(allocator, cell);

    // The line is full: the cursor stays on the last column and the wrap is
    // deferred until the next character arrives.
    try std.testing.expectEqual(@as(usize, 2), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_y);
    try std.testing.expect(my_grid.wrap_pending);
    try std.testing.expectEqual(@as(usize, 3), my_grid.rowCount()); // nothing scrolled yet

    const filled = rowCells(&my_grid, 0);
    try std.testing.expectEqual(@as(u32, 'X'), filled[0].unicode);
    try std.testing.expectEqual(@as(u32, 'X'), filled[1].unicode);
    try std.testing.expectEqual(@as(u32, 'X'), filled[2].unicode);
    try std.testing.expect(!my_grid.visibleRow(0).?.wrapped);

    // The 4th character consumes the pending wrap: it lands at column 0 of the
    // next row, and row 0 is now flagged as soft-wrapped.
    try my_grid.putChar(allocator, cell);
    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_y);
    try std.testing.expect(!my_grid.wrap_pending);
    try std.testing.expect(my_grid.visibleRow(0).?.wrapped);
    try std.testing.expectEqual(@as(u32, 'X'), rowCells(&my_grid, 1)[0].unicode);
}

test "Grid cursor movement cancels a pending wrap" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 2,
        .rows_width = 2,
    };
    defer my_grid.deinit(allocator);

    const cell = Cell{ .unicode = 'X', .fg_color = .white, .bg_color = .black, .flags = .{} };
    try my_grid.putChar(allocator, cell);
    try my_grid.putChar(allocator, cell);
    try std.testing.expect(my_grid.wrap_pending);

    // Moving the cursor horizontally cancels the wrap, so the next character
    // overwrites the second column instead of starting a new row.
    my_grid.clearWrapPending();
    my_grid.cursor_x = 0;
    try my_grid.putChar(allocator, cell);

    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_y);
    try std.testing.expectEqual(@as(usize, 2), my_grid.rowCount()); // still no scroll
}

test "Grid Linefeed at Viewport Bottom (Scrolling)" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 3,
        .rows_width = 5,
    };
    defer my_grid.deinit(allocator);

    // Move to bottom row
    try my_grid.linefeed(allocator); // cursor_y = 1
    try my_grid.linefeed(allocator); // cursor_y = 2
    try std.testing.expectEqual(@as(usize, 2), my_grid.cursor_y);
    try std.testing.expectEqual(@as(usize, 3), my_grid.rowCount());

    // Linefeed at the bottom: should trigger scroll (append row, keep cursor_y at 2)
    try my_grid.linefeed(allocator);
    try std.testing.expectEqual(@as(usize, 2), my_grid.cursor_y);
    try std.testing.expectEqual(@as(usize, 4), my_grid.rowCount());
    try std.testing.expectEqual(@as(usize, 0), my_grid.scroll_offset);
}

test "Grid Scrollback Navigation and visibleRow" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 3,
        .rows_width = 5,
    };
    defer my_grid.deinit(allocator);

    // Write a tag character ('A' through 'H') in each of the 8 lines
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        const cell = Cell{ .unicode = 'A' + i, .fg_color = .white, .bg_color = .black, .flags = .{} };
        try my_grid.putChar(allocator, cell);
        if (i < 7) {
            try my_grid.linefeed(allocator);
            my_grid.carriageReturn();
        }
    }

    // Total rows should be exactly 8
    const total_rows = my_grid.rowCount();
    try std.testing.expectEqual(@as(usize, 8), total_rows);

    const max_offset = my_grid.maxScrollOffset();
    try std.testing.expectEqual(@as(usize, 5), max_offset); // 8 - 3 = 5

    // At bottom (scroll_offset = 0), the viewport should show the last 3 rows: 'F', 'G', 'H'
    {
        try std.testing.expectEqual(@as(u32, 'F'), rowCells(&my_grid, 0)[0].unicode);
        try std.testing.expectEqual(@as(u32, 'G'), rowCells(&my_grid, 1)[0].unicode);
        try std.testing.expectEqual(@as(u32, 'H'), rowCells(&my_grid, 2)[0].unicode);
    }

    // Scroll up by 2: should show 'D', 'E', 'F'
    my_grid.scrollUp(2);
    try std.testing.expectEqual(@as(usize, 2), my_grid.scroll_offset);
    {
        try std.testing.expectEqual(@as(u32, 'D'), rowCells(&my_grid, 0)[0].unicode);
        try std.testing.expectEqual(@as(u32, 'E'), rowCells(&my_grid, 1)[0].unicode);
        try std.testing.expectEqual(@as(u32, 'F'), rowCells(&my_grid, 2)[0].unicode);
    }

    // Scroll down by 1: should show 'E', 'F', 'G'
    my_grid.scrollDown(1);
    try std.testing.expectEqual(@as(usize, 1), my_grid.scroll_offset);
    {
        try std.testing.expectEqual(@as(u32, 'E'), rowCells(&my_grid, 0)[0].unicode);
        try std.testing.expectEqual(@as(u32, 'F'), rowCells(&my_grid, 1)[0].unicode);
        try std.testing.expectEqual(@as(u32, 'G'), rowCells(&my_grid, 2)[0].unicode);
    }

    // Scroll up excessively
    my_grid.scrollUp(100);
    try std.testing.expectEqual(max_offset, my_grid.scroll_offset);

    // Scroll to bottom
    my_grid.scrollToBottom();
    try std.testing.expectEqual(@as(usize, 0), my_grid.scroll_offset);
}

test "Grid Scroll Offset Tracking on Appends" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 3,
        .rows_width = 5,
    };
    defer my_grid.deinit(allocator);

    // Populate lines to have some scrollback
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try my_grid.linefeed(allocator);
    }

    // Scroll up by 2
    my_grid.scrollUp(2);
    const initial_offset = my_grid.scroll_offset;
    try std.testing.expect(initial_offset > 0);

    // Trigger an append via linefeed at the bottom
    // To do this we temporarily move cursor to bottom and linefeed
    const saved_y = my_grid.cursor_y;
    my_grid.cursor_y = my_grid.visable_rows - 1;
    try my_grid.linefeed(allocator);
    my_grid.cursor_y = saved_y;

    // Scroll offset should have incremented to keep viewport content unchanged
    try std.testing.expectEqual(initial_offset + 1, my_grid.scroll_offset);
}

test "Grid Resizing Width Changes" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 3,
        .rows_width = 10,
    };
    defer my_grid.deinit(allocator);

    const cell = Cell{ .unicode = 'A', .fg_color = .white, .bg_color = .black, .flags = .{} };
    // Fill the first row up to index 8
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        try my_grid.putChar(allocator, cell);
    }
    try std.testing.expectEqual(@as(usize, 8), my_grid.cursor_x);

    // Shrink width to 5
    try my_grid.resizeVisable(allocator, 3, 5);
    try std.testing.expectEqual(@as(usize, 5), my_grid.rows_width);
    try std.testing.expectEqual(@as(usize, 4), my_grid.cursor_x); // Clamped from 8 to 4

    // Check cells were truncated to length 5
    try std.testing.expectEqual(@as(usize, 5), rowCells(&my_grid, 0).len);

    // Grow width to 8
    try my_grid.resizeVisable(allocator, 3, 8);
    try std.testing.expectEqual(@as(usize, 8), my_grid.rows_width);
    // New cells should be defaults
    const grown = rowCells(&my_grid, 0);
    try std.testing.expectEqual(@as(usize, 8), grown.len);
    try std.testing.expectEqual(@as(u32, 0), grown[6].unicode);
}

test "Grid Resizing Height Changes" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{
        .visable_rows = 5,
        .rows_width = 5,
    };
    defer my_grid.deinit(allocator);

    my_grid.cursor_y = 4;

    // Shrink height
    try my_grid.resizeVisable(allocator, 3, 5);
    try std.testing.expectEqual(@as(usize, 3), my_grid.visable_rows);
    try std.testing.expectEqual(@as(usize, 2), my_grid.cursor_y); // Clamped

    // Grow height
    try my_grid.resizeVisable(allocator, 8, 5);
    try std.testing.expectEqual(@as(usize, 8), my_grid.visable_rows);
    // Should have appended rows to fill height
    try std.testing.expect(my_grid.rowCount() >= 8);
}

test "deleteChars shifts cells left and blanks tail" {
    const allocator = std.testing.allocator;
    // Grid: 1 row, 6 columns wide.  Write "ABCDEF" then place cursor at col 1.
    // CSI 2 P  → delete 2 chars at col 1 → "ACDEF" becomes "ADEF  "
    var my_grid = Grid{ .visable_rows = 1, .rows_width = 6 };
    defer my_grid.deinit(allocator);

    const mk = struct {
        fn cell(ch: u32) Cell {
            return .{ .unicode = ch, .fg_color = .white, .bg_color = .black, .flags = .{} };
        }
    };

    for ("ABCDEF") |ch| try my_grid.putChar(allocator, mk.cell(ch));

    // Place cursor at column 1 (on 'B').
    my_grid.cursor_x = 1;

    // Delete 2 characters — 'B' and 'C' should vanish, 'DEF' slides left,
    // rightmost 2 cells become blank.
    try my_grid.deleteChars(allocator, 2);

    const row = rowCells(&my_grid, 0);
    try std.testing.expectEqual(@as(u32, 'A'), row[0].unicode);
    try std.testing.expectEqual(@as(u32, 'D'), row[1].unicode);
    try std.testing.expectEqual(@as(u32, 'E'), row[2].unicode);
    try std.testing.expectEqual(@as(u32, 'F'), row[3].unicode);
    // try std.testing.expectEqual(@as(u32, 0),   row[4].unicode); // blank
    // try std.testing.expectEqual(@as(u32, 0),   row[5].unicode); // blank

    // Cursor must not have moved.
    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_x);
}

test "deleteChars clamps when n exceeds remaining columns" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{ .visable_rows = 1, .rows_width = 4 };
    defer my_grid.deinit(allocator);

    const mk = struct {
        fn cell(ch: u32) Cell {
            return .{ .unicode = ch, .fg_color = .white, .bg_color = .black, .flags = .{} };
        }
    };

    for ("ABCD") |ch| try my_grid.putChar(allocator, mk.cell(ch));

    // Cursor at col 2, delete 100 chars — should blank from col 2 to end.
    my_grid.cursor_x = 2;
    try my_grid.deleteChars(allocator, 100);

    const row = rowCells(&my_grid, 0);
    try std.testing.expectEqual(@as(u32, 'A'), row[0].unicode);
    try std.testing.expectEqual(@as(u32, 'B'), row[1].unicode);
    try std.testing.expectEqual(@as(u32, 0), row[2].unicode); // blanked
    try std.testing.expectEqual(@as(u32, 0), row[3].unicode); // blanked
}

test "deleteChars at end of line is a no-op" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{ .visable_rows = 1, .rows_width = 3 };
    defer my_grid.deinit(allocator);

    const mk = struct {
        fn cell(ch: u32) Cell {
            return .{ .unicode = ch, .fg_color = .white, .bg_color = .black, .flags = .{} };
        }
    };

    for ("ABC") |ch| try my_grid.putChar(allocator, mk.cell(ch));

    // Cursor past the last column — nothing to delete.
    my_grid.cursor_x = 3;
    try my_grid.deleteChars(allocator, 1);

    const row = rowCells(&my_grid, 0);
    try std.testing.expectEqual(@as(u32, 'A'), row[0].unicode);
    try std.testing.expectEqual(@as(u32, 'B'), row[1].unicode);
    try std.testing.expectEqual(@as(u32, 'C'), row[2].unicode);
}

fn expectRgba(colors: []const u8, row: usize, col: usize, cols: usize, expected: RGBA) !void {
    const idx = (row * cols + col) * 4;
    const rgba: *const [4]u8 = @ptrCast(&expected);
    try std.testing.expectEqual(@as(u8, rgba[0]), colors[idx]);
    try std.testing.expectEqual(@as(u8, rgba[1]), colors[idx + 1]);
    try std.testing.expectEqual(@as(u8, rgba[2]), colors[idx + 2]);
    try std.testing.expectEqual(@as(u8, rgba[3]), colors[idx + 3]);
}

test "fillBackgroundColors defaults to opaque black across the viewport" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{ .visable_rows = 3, .rows_width = 2 };
    defer my_grid.deinit(allocator);

    const colors = try allocator.alloc(u8, 3 * 2 * 4);
    defer allocator.free(colors);

    my_grid.fillBackgroundColors(colors);

    var i: usize = 0;
    while (i < colors.len) : (i += 4) {
        try std.testing.expectEqual(@as(u8, 0), colors[i]);
        try std.testing.expectEqual(@as(u8, 0), colors[i + 1]);
        try std.testing.expectEqual(@as(u8, 0), colors[i + 2]);
        try std.testing.expectEqual(@as(u8, 255), colors[i + 3]);
    }
}

test "fillBackgroundColors writes each cell's background at its own position" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{ .visable_rows = 2, .rows_width = 3 };
    defer my_grid.deinit(allocator);

    const red = RGBA.rgba(205, 0, 0, 255);
    const blue = RGBA.rgba(0, 0, 205, 255);

    try my_grid.putChar(allocator, .{ .unicode = 'A', .fg_color = .white, .bg_color = red, .flags = .{} });
    try my_grid.putChar(allocator, .{ .unicode = 'B', .fg_color = .white, .bg_color = blue, .flags = .{} });

    const colors = try allocator.alloc(u8, 2 * 3 * 4);
    defer allocator.free(colors);

    my_grid.fillBackgroundColors(colors);

    try expectRgba(colors, 0, 0, 3, red);
    try expectRgba(colors, 0, 1, 3, blue);
    try expectRgba(colors, 0, 2, 3, RGBA.black);
    try expectRgba(colors, 1, 0, 3, RGBA.black);
    try expectRgba(colors, 1, 1, 3, RGBA.black);
    try expectRgba(colors, 1, 2, 3, RGBA.black);
}

test "fillBackgroundColors reflects the scrolled viewport" {
    const allocator = std.testing.allocator;
    var my_grid = Grid{ .visable_rows = 2, .rows_width = 1 };
    defer my_grid.deinit(allocator);

    // bottom row: red, second-from-bottom (still visible): blue,
    // third row (older, initially in the viewport): green.
    try my_grid.putChar(allocator, .{ .unicode = 'A', .fg_color = .white, .bg_color = RGBA.rgba(0, 205, 0, 255), .flags = .{} });
    try my_grid.linefeed(allocator);
    my_grid.carriageReturn();
    try my_grid.putChar(allocator, .{ .unicode = 'B', .fg_color = .white, .bg_color = RGBA.rgba(0, 0, 205, 255), .flags = .{} });
    try my_grid.linefeed(allocator);
    my_grid.carriageReturn();
    try my_grid.putChar(allocator, .{ .unicode = 'C', .fg_color = .white, .bg_color = RGBA.rgba(205, 0, 0, 255), .flags = .{} });

    const colors = try allocator.alloc(u8, 2 * 1 * 4);
    defer allocator.free(colors);

    // At the bottom, visible rows are [blue row, red row].
    my_grid.fillBackgroundColors(colors);
    try expectRgba(colors, 0, 0, 1, RGBA.rgba(0, 0, 205, 255));
    try expectRgba(colors, 1, 0, 1, RGBA.rgba(205, 0, 0, 255));

    // Scrolling up reveals [green row, blue row].
    my_grid.scrollUp(1);
    my_grid.fillBackgroundColors(colors);
    try expectRgba(colors, 0, 0, 1, RGBA.rgba(0, 205, 0, 255));
    try expectRgba(colors, 1, 0, 1, RGBA.rgba(0, 0, 205, 255));
}
