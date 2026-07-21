const std = @import("std");
const grid = @import("root.zig");
const Grid = grid.Grid;
const Row = grid.Row;
const Cell = grid.Cell;

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
    const visible = my_grid.visibleRows();
    try std.testing.expect(visible.len >= 1);
    try std.testing.expectEqual(@as(u32, 'A'), visible[0].backing_storage.items[0].unicode);
    try std.testing.expectEqual(@as(u32, 'B'), visible[0].backing_storage.items[1].unicode);

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

    // Now cursor_x has wrapped back to 0 and cursor_y advanced to 1
    try std.testing.expectEqual(@as(usize, 0), my_grid.cursor_x);
    try std.testing.expectEqual(@as(usize, 1), my_grid.cursor_y);

    const visible = my_grid.visibleRows();
    try std.testing.expectEqual(@as(u32, 'X'), visible[0].backing_storage.items[0].unicode);
    try std.testing.expectEqual(@as(u32, 'X'), visible[0].backing_storage.items[1].unicode);
    try std.testing.expectEqual(@as(u32, 'X'), visible[0].backing_storage.items[2].unicode);
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
    try std.testing.expectEqual(@as(usize, 3), my_grid.rows.items.len);

    // Linefeed at the bottom: should trigger scroll (append row, keep cursor_y at 2)
    try my_grid.linefeed(allocator);
    try std.testing.expectEqual(@as(usize, 2), my_grid.cursor_y);
    try std.testing.expectEqual(@as(usize, 4), my_grid.rows.items.len);
    try std.testing.expectEqual(@as(usize, 0), my_grid.scroll_offset);
}

test "Grid Scrollback Navigation and visibleRows" {
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
    const total_rows = my_grid.rows.items.len;
    try std.testing.expectEqual(@as(usize, 8), total_rows);

    const max_offset = my_grid.maxScrollOffset();
    try std.testing.expectEqual(@as(usize, 5), max_offset); // 8 - 3 = 5

    // At bottom (scroll_offset = 0), visibleRows should show the last 3 rows: 'F', 'G', 'H'
    {
        const visible = my_grid.visibleRows();
        try std.testing.expectEqual(@as(usize, 3), visible.len);
        try std.testing.expectEqual(@as(u32, 'F'), visible[0].backing_storage.items[0].unicode);
        try std.testing.expectEqual(@as(u32, 'G'), visible[1].backing_storage.items[0].unicode);
        try std.testing.expectEqual(@as(u32, 'H'), visible[2].backing_storage.items[0].unicode);
    }

    // Scroll up by 2: should show 'D', 'E', 'F'
    my_grid.scrollUp(2);
    try std.testing.expectEqual(@as(usize, 2), my_grid.scroll_offset);
    {
        const visible = my_grid.visibleRows();
        try std.testing.expectEqual(@as(u32, 'D'), visible[0].backing_storage.items[0].unicode);
        try std.testing.expectEqual(@as(u32, 'E'), visible[1].backing_storage.items[0].unicode);
        try std.testing.expectEqual(@as(u32, 'F'), visible[2].backing_storage.items[0].unicode);
    }

    // Scroll down by 1: should show 'E', 'F', 'G'
    my_grid.scrollDown(1);
    try std.testing.expectEqual(@as(usize, 1), my_grid.scroll_offset);
    {
        const visible = my_grid.visibleRows();
        try std.testing.expectEqual(@as(u32, 'E'), visible[0].backing_storage.items[0].unicode);
        try std.testing.expectEqual(@as(u32, 'F'), visible[1].backing_storage.items[0].unicode);
        try std.testing.expectEqual(@as(u32, 'G'), visible[2].backing_storage.items[0].unicode);
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
    const visible = my_grid.visibleRows();
    try std.testing.expectEqual(@as(usize, 5), visible[0].len());

    // Grow width to 8
    try my_grid.resizeVisable(allocator, 3, 8);
    try std.testing.expectEqual(@as(usize, 8), my_grid.rows_width);
    // New cells should be defaults
    try std.testing.expectEqual(@as(usize, 8), visible[0].len());
    try std.testing.expectEqual(@as(u32, 0), visible[0].backing_storage.items[6].unicode);
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
    try std.testing.expect(my_grid.rows.items.len >= 8);
}
