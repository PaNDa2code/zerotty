//! Terminal cell grid: the live screen plus an optional scrollback history.
//!
//! This implementation is intentionally simple:
//!
//!   * rows are stored in a `std.ArrayList(RowData)`;
//!   * every row owns its own `[]Cell` allocation;
//!   * rows are never recycled in place, so scrolling and resizing are easy to
//!     follow.
//!
//! It is not optimized. The flat ring that used to live here can come back
//! later once the behavior is settled.
//!
//! Logical row 0 is the oldest row still kept. The last `visable_rows` logical
//! rows are the live screen; everything before them is scrollback. Every row is
//! exactly `rows_width` cells wide. A blank cell is `Cell.default`.

const std = @import("std");
const Grid = @This();
const Row = @import("Row.zig");
const grid = @import("root.zig");
const Cell = grid.Cell;
const color = @import("zerotty").terminal.color;
const ser = @import("serialize.zig");
pub const serialize = ser.serialize;
pub const deserialize = ser.deserialize;

/// One stored row. The grid owns `cells` and frees it in `deinit`.
pub const RowData = struct {
    cells: []Cell,
    wrapped: bool = false,
};

/// All stored rows, oldest first.
rows: std.ArrayList(RowData) = .empty,

/// Viewport height in rows.
visable_rows: usize,
/// Viewport width in columns. Change it through `resizeVisable`, not directly.
rows_width: usize,

/// Maximum number of history rows kept above the live screen.
max_scrollback: usize = 10_000,

scroll_offset: usize = 0,

/// Background used for blank (never-written/erased) cells.
bg_color: color.RGBA = .black,

scroll_top: usize = 0,
scroll_bottom: usize = 0,

cursor_x: usize = 0,
cursor_y: usize = 0,

/// Deferred wrap ("wrap pending", DEC STD 070 §5.2). Printing in the last
/// column leaves the cursor there and only sets this flag; the linefeed (and
/// the scroll that may come with it) happens when the NEXT character is
/// printed. Without it, filling the last cell would scroll the screen on its
/// own, before there is any content to scroll for.
///
/// Any explicit cursor movement clears the flag, so the next character lands
/// where the cursor was moved to.
wrap_pending: bool = false,

// ---------------------------------------------------------------------------
// Row helpers
// ---------------------------------------------------------------------------

/// Logical index of the first live-screen row.
inline fn firstLive(self: *const Grid) usize {
    return self.rows.items.len -| self.visable_rows;
}

/// Logical index of the row under the cursor.
fn liveRowIndex(self: *const Grid) usize {
    const y = @min(self.cursor_y, self.visable_rows -| 1);
    return self.firstLive() + y;
}

fn makeRow(
    self: *const Grid,
    allocator: std.mem.Allocator,
    cells: []const Cell,
    wrapped: bool,
) !RowData {
    const dst = try allocator.alloc(Cell, self.rows_width);
    errdefer allocator.free(dst);
    @memset(dst, Cell.default);

    const n = @min(dst.len, cells.len);
    if (n > 0) @memcpy(dst[0..n], cells[0..n]);

    return .{ .cells = dst, .wrapped = wrapped };
}

fn appendRow(
    self: *Grid,
    allocator: std.mem.Allocator,
    cells: []const Cell,
    wrapped: bool,
) !void {
    const row = try self.makeRow(allocator, cells, wrapped);
    errdefer allocator.free(row.cells);
    try self.rows.append(allocator, row);
}

fn appendBlankRow(self: *Grid, allocator: std.mem.Allocator) !void {
    try self.appendRow(allocator, &.{}, false);
}

/// Ensure the live screen exists (`rows.len >= visable_rows`). Cheap no-op
/// after first use, so it is safe to call unconditionally.
fn ensureLiveRows(self: *Grid, allocator: std.mem.Allocator) !void {
    if (self.rows_width == 0) return;
    while (self.rows.items.len < self.visable_rows) {
        try self.appendBlankRow(allocator);
    }
}

/// Drop the oldest `n` rows. This never allocates, so it cannot fail.
fn dropOldestRows(self: *Grid, allocator: std.mem.Allocator, n: usize) void {
    const count = @min(n, self.rows.items.len);
    if (count == 0) return;

    for (self.rows.items[0..count]) |row| {
        allocator.free(row.cells);
    }

    const remaining = self.rows.items.len - count;
    std.mem.copyForwards(RowData, self.rows.items[0..remaining], self.rows.items[count..]);
    self.rows.shrinkRetainingCapacity(remaining);
}

fn trimScrollback(self: *Grid, allocator: std.mem.Allocator) void {
    const max_rows = self.visable_rows +| self.max_scrollback;
    if (self.rows.items.len > max_rows) {
        self.dropOldestRows(allocator, self.rows.items.len - max_rows);
    }
}

/// Add a blank row at the bottom of the buffer, scrolling the live screen.
fn pushRow(self: *Grid, allocator: std.mem.Allocator) !void {
    try self.appendBlankRow(allocator);
    self.trimScrollback(allocator);

    // Keep a scrolled-back viewport anchored on the same content.
    if (self.scroll_offset > 0) {
        self.scroll_offset = @min(self.scroll_offset +| 1, self.maxScrollOffset());
    }
}

/// Number of non-blank cells at the end of `cells`, used when reflowing.
fn usedLen(cells: []const Cell) usize {
    var i = cells.len;
    while (i > 0) : (i -= 1) {
        if (!std.meta.eql(cells[i - 1], Cell.default)) return i;
    }
    return 0;
}

/// The active scrolling region, in live-screen row coordinates.
///
/// `scroll_top == scroll_bottom` is the default "no region" state and means
/// the whole live screen.
fn scrollRegionBounds(self: *const Grid) struct { top: usize, bottom: usize } {
    if (self.visable_rows == 0) return .{ .top = 0, .bottom = 0 };

    const max = self.visable_rows - 1;
    const top = @min(self.scroll_top, max);
    const bottom = @min(self.scroll_bottom, max);

    if (bottom <= top) return .{ .top = 0, .bottom = max };
    return .{ .top = top, .bottom = bottom };
}

fn resetScrollRegion(self: *Grid) void {
    self.scroll_top = 0;
    self.scroll_bottom = self.visable_rows -| 1;
}

fn isFullScrollRegion(self: *const Grid) bool {
    const region = self.scrollRegionBounds();
    return region.top == 0 and region.bottom == (self.visable_rows -| 1);
}

fn blankRowCells(row: *RowData) void {
    @memset(row.cells, Cell.default);
    row.wrapped = false;
}

/// Rotate live rows `[top, bottom]` up by `n`, blanking the rows that fall off
/// the bottom. This never adds scrollback.
fn scrollRowsUp(self: *Grid, top: usize, bottom: usize, n: usize) void {
    if (top > bottom or bottom >= self.visable_rows) return;

    const count = bottom - top + 1;
    const shift = @min(n, count);
    if (shift == 0) return;

    const first = self.firstLive() + top;
    const end = self.firstLive() + bottom + 1;
    std.mem.rotate(RowData, self.rows.items[first..end], shift);

    for (self.rows.items[end - shift .. end]) |*row| {
        blankRowCells(row);
    }
}

/// Rotate live rows `[top, bottom]` down by `n`, blanking the rows that fall off
/// the top. This never adds scrollback.
fn scrollRowsDown(self: *Grid, top: usize, bottom: usize, n: usize) void {
    if (top > bottom or bottom >= self.visable_rows) return;

    const count = bottom - top + 1;
    const shift = @min(n, count);
    if (shift == 0) return;

    const first = self.firstLive() + top;
    const end = self.firstLive() + bottom + 1;
    std.mem.rotate(RowData, self.rows.items[first..end], count - shift);

    for (self.rows.items[first .. first + shift]) |*row| {
        blankRowCells(row);
    }
}

// ---------------------------------------------------------------------------
// Viewport
// ---------------------------------------------------------------------------

/// Resize the visible viewport.
///
/// * Width: rows are reflowed at the new width, using `wrapped` to find logical
///   lines first. This keeps text intact when the terminal shrinks and then
///   grows again.
/// * Height, shrinking: the top rows of the old screen move into scrollback.
/// * Height, growing: rows are pulled back out of scrollback first; blank rows
///   are appended only if scrollback runs out.
///
/// Returns `error.InvalidSize` for a zero dimension. On any error the grid is
/// left unchanged.
pub fn resizeVisable(
    self: *Grid,
    allocator: std.mem.Allocator,
    visable_rows: usize,
    rows_width: usize,
) !void {
    if (self.visable_rows == visable_rows and self.rows_width == rows_width)
        return;
    if (visable_rows == 0 or rows_width == 0) return error.InvalidSize;

    // The grid was never given a usable width. Throw away anything left over
    // from a zero-width setup and start clean.
    if (self.rows_width == 0) {
        for (self.rows.items) |row| allocator.free(row.cells);
        self.rows.clearRetainingCapacity();

        self.rows_width = rows_width;
        self.visable_rows = visable_rows;
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.wrap_pending = false;
        self.scroll_offset = 0;
        self.resetScrollRegion();
        try self.ensureLiveRows(allocator);
        return;
    }

    if (self.rows_width != rows_width) {
        try self.reflow(allocator, visable_rows, rows_width);
        self.resetScrollRegion();
        return;
    }

    // Height-only change. Remember where the cursor is in absolute row
    // coordinates before changing how many rows are considered live.
    const old_first_live = self.firstLive();
    const cursor_abs = old_first_live + self.cursor_y;

    self.visable_rows = visable_rows;
    try self.ensureLiveRows(allocator);

    const max_rows = self.visable_rows +| self.max_scrollback;
    var dropped: usize = 0;
    if (self.rows.items.len > max_rows) {
        dropped = self.rows.items.len - max_rows;
        self.dropOldestRows(allocator, dropped);
    }

    const new_first_live = self.firstLive();
    const adjusted_cursor = cursor_abs -| dropped;
    self.cursor_y = @min(adjusted_cursor -| new_first_live, self.visable_rows - 1);
    self.cursor_x = @min(self.cursor_x, self.rows_width - 1);
    self.wrap_pending = false;
    self.resetScrollRegion();
    self.clampScrollOffset();
}

/// Re-split every logical line at the new width.
///
/// `wrapped` marks a row that continues on the next row, so a logical line is
/// found by walking until the first row that is not wrapped. This is what lets
/// a width change preserve the text instead of truncating it.
fn reflow(
    self: *Grid,
    allocator: std.mem.Allocator,
    new_visable_rows: usize,
    new_cols: usize,
) !void {
    std.debug.assert(self.rows_width > 0);

    // Materialize the live screen first so an empty grid still gets padded.
    try self.ensureLiveRows(allocator);

    const old_cols = self.rows_width;
    const old_first_live = self.firstLive();
    const old_cursor_abs = old_first_live + self.cursor_y;
    const old_wrap_pending = self.wrap_pending;

    // Build the replacement rows separately. If anything fails, the old grid
    // is still intact and the caller sees the original contents.
    var new_rows: std.ArrayList(RowData) = .empty;
    errdefer {
        for (new_rows.items) |row| allocator.free(row.cells);
        new_rows.deinit(allocator);
    }

    var cursor_new_row: ?usize = null;
    var cursor_new_col: usize = 0;
    var cursor_at_end_full_row = false;

    var start: usize = 0;
    while (start < self.rows.items.len) {
        // Find the end of this logical line.
        var end = start;
        while (end + 1 < self.rows.items.len and self.rows.items[end].wrapped) {
            end += 1;
        }

        // A non-final row is full, so it contributes `old_cols` cells. The
        // final row may have trailing blanks that should not be preserved.
        var content_len = (end - start) * old_cols;
        content_len += usedLen(self.rows.items[end].cells);

        // Map the cursor into the logical line. A cursor that sits after the
        // content (normal when the user just typed the last character) may
        // need an extra blank cell so it still has somewhere to render.
        var cursor_offset: ?usize = null;
        var cursor_on_this_line = false;
        if (old_cursor_abs >= start and old_cursor_abs <= end) {
            cursor_on_this_line = true;
            const off = (old_cursor_abs - start) * old_cols + self.cursor_x;
            cursor_offset = off;

            if (off >= content_len) {
                if (off == content_len and content_len > 0 and content_len % new_cols == 0) {
                    // The content exactly fills a row. The cursor belongs on
                    // the last cell of that row, with a pending wrap.
                    cursor_at_end_full_row = true;
                } else {
                    content_len = @max(content_len, off + 1);
                }
            }
        }

        const line_rows = @max(1, (content_len + new_cols - 1) / new_cols);
        const line_start_new = new_rows.items.len;

        for (0..line_rows) |r| {
            const cells = try allocator.alloc(Cell, new_cols);
            errdefer allocator.free(cells);
            @memset(cells, Cell.default);

            const base = r * new_cols;
            const remaining = content_len -| base;
            const count = @min(new_cols, remaining);

            for (0..count) |i| {
                const off = base + i;
                const src_row = start + off / old_cols;
                const src_col = off % old_cols;
                cells[i] = self.rows.items[src_row].cells[src_col];
            }

            try new_rows.append(allocator, .{
                .cells = cells,
                .wrapped = r + 1 < line_rows,
            });

            if (!cursor_at_end_full_row) {
                if (cursor_offset) |off| {
                    if (off >= base and off < base + new_cols) {
                        cursor_new_row = new_rows.items.len - 1;
                        cursor_new_col = off - base;
                    }
                }
            }
        }

        if (cursor_on_this_line and cursor_at_end_full_row) {
            cursor_new_row = line_start_new + line_rows - 1;
            cursor_new_col = new_cols - 1;
        }

        start = end + 1;
    }

    // Pad the live screen if reflow produced fewer rows than the new viewport.
    while (new_rows.items.len < new_visable_rows) {
        const cells = try allocator.alloc(Cell, new_cols);
        errdefer allocator.free(cells);
        @memset(cells, Cell.default);
        try new_rows.append(allocator, .{ .cells = cells, .wrapped = false });
    }

    // Respect the scrollback limit. With the default of zero this keeps only
    // the live screen, exactly like `pushRow`.
    const max_rows = new_visable_rows +| self.max_scrollback;
    var dropped: usize = 0;
    if (new_rows.items.len > max_rows) {
        dropped = new_rows.items.len - max_rows;
        for (new_rows.items[0..dropped]) |row| allocator.free(row.cells);
        const remaining = new_rows.items.len - dropped;
        std.mem.copyForwards(RowData, new_rows.items[0..remaining], new_rows.items[dropped..]);
        new_rows.shrinkRetainingCapacity(remaining);
    }

    // Swap in the new rows and free the old ones.
    for (self.rows.items) |row| allocator.free(row.cells);
    self.rows.deinit(allocator);
    self.rows = new_rows;

    self.rows_width = new_cols;
    self.visable_rows = new_visable_rows;

    const new_first_live = self.firstLive();
    if (cursor_new_row) |row| {
        const cursor_was_dropped = row < dropped;
        const adjusted = row -| dropped;
        self.cursor_y = @min(adjusted -| new_first_live, self.visable_rows - 1);
        self.cursor_x = @min(cursor_new_col, new_cols - 1);
        self.wrap_pending = !cursor_was_dropped and
            (old_wrap_pending or cursor_at_end_full_row) and
            self.cursor_x == new_cols - 1;
    } else {
        self.cursor_x = @min(self.cursor_x, new_cols - 1);
        self.cursor_y = @min(self.cursor_y, self.visable_rows - 1);
        self.wrap_pending = false;
    }

    self.clampScrollOffset();
}

/// Total rows currently stored (scrollback + live screen).
pub fn rowCount(self: *const Grid) usize {
    return self.rows.items.len;
}

/// How many rows back into history the viewport is currently allowed
/// to scroll (0 if there's no scrollback beyond the visible area).
pub fn maxScrollOffset(self: *const Grid) usize {
    return self.rows.items.len -| self.visable_rows;
}

fn clampScrollOffset(self: *Grid) void {
    const max = self.maxScrollOffset();
    if (self.scroll_offset > max) self.scroll_offset = max;
}

/// Scroll the viewport up (towards older history) by `n` rows.
pub fn scrollUp(self: *Grid, n: usize) void {
    self.scroll_offset = @min(self.scroll_offset +| n, self.maxScrollOffset());
}

/// Scroll the viewport down (towards the live output) by `n` rows.
pub fn scrollDown(self: *Grid, n: usize) void {
    self.scroll_offset -|= n;
}

/// Jump straight back to the live/bottom position.
pub fn scrollToBottom(self: *Grid) void {
    self.scroll_offset = 0;
}

/// Row `y` (0 = top) of the viewport, taking `scroll_offset` into account.
/// Returns null if `y` is outside the viewport or nothing has been stored yet
/// (in which case every cell is blank).
pub fn visibleRow(self: *const Grid, y: usize) ?Row {
    if (y >= self.visable_rows or self.rows.items.len < self.visable_rows) return null;

    const offset = @min(self.scroll_offset, self.maxScrollOffset());
    const index = self.rows.items.len - self.visable_rows - offset + y;
    const row = self.rows.items[index];
    return .{ .cells = row.cells, .wrapped = row.wrapped };
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// Write a cell at the cursor position and advance the cursor.
///
/// Reaching the right edge does not wrap immediately: the cursor stays on the
/// last column with `wrap_pending` set, and the wrap happens on the next call
/// (see `wrap_pending`).
pub fn putChar(self: *Grid, allocator: std.mem.Allocator, cell: Cell) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    self.cursor_y = @min(self.cursor_y, self.visable_rows - 1);

    if (self.wrap_pending) {
        self.wrap_pending = false;
        self.rows.items[self.liveRowIndex()].wrapped = true;
        try self.linefeed(allocator);
        self.cursor_x = 0;
    } else if (self.cursor_x >= self.rows_width) {
        // Only reachable if the caller moved the cursor past the edge by hand.
        self.rows.items[self.liveRowIndex()].wrapped = true;
        try self.linefeed(allocator);
        self.cursor_x = 0;
    }

    self.rows.items[self.liveRowIndex()].cells[self.cursor_x] = cell;

    self.cursor_x += 1;
    if (self.cursor_x >= self.rows_width) {
        // Keep `cursor_x` in range so the cursor still renders on the last
        // cell; `wrap_pending` remembers that the row is full.
        self.cursor_x = self.rows_width - 1;
        self.wrap_pending = true;
    }
}

/// Move the cursor down one line. If the cursor is at the bottom margin of the
/// active scroll region, scroll only that region. A full-screen region keeps the
/// normal scrollback behavior. Cancels a pending wrap.
pub fn linefeed(self: *Grid, allocator: std.mem.Allocator) !void {
    self.wrap_pending = false;
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    self.cursor_y = @min(self.cursor_y, self.visable_rows - 1);

    const region = self.scrollRegionBounds();
    if (self.cursor_y == region.bottom) {
        try self.scrollRegionUp(allocator, 1);
        self.cursor_y = region.bottom;
        return;
    }

    if (self.cursor_y + 1 < self.visable_rows) {
        self.cursor_y += 1;
    } else {
        self.cursor_y = self.visable_rows - 1;
    }
}

/// Move cursor to column 0 of the current line. Cancels a pending wrap.
pub fn carriageReturn(self: *Grid) void {
    self.cursor_x = 0;
    self.wrap_pending = false;
}

/// Cancel a pending wrap without moving the cursor. Called before any explicit
/// cursor movement (CUU, CUD, CUF, CUB, CUP, backspace, ...).
pub fn clearWrapPending(self: *Grid) void {
    self.wrap_pending = false;
}

// ---------------------------------------------------------------------------
// Erasing
// ---------------------------------------------------------------------------

/// Blank columns `[start_col, end_col)` of a logical row. Cannot fail.
fn eraseCells(self: *Grid, logical: usize, start_col: usize, end_col: usize) void {
    if (logical >= self.rows.items.len) return;

    const cols = self.rows_width;
    const end = @min(end_col, cols);
    const start = @min(start_col, end);
    const row = &self.rows.items[logical];

    @memset(row.cells[start..end], Cell.default);
    if (start == 0 and end == cols) row.wrapped = false;
}

pub const EraseMode = enum(usize) {
    /// Cursor to end of screen (ED 0).
    to_end = 0,
    /// Start of screen to cursor (ED 1).
    to_start = 1,
    /// Whole live screen (ED 2).
    all = 2,
    /// Scrollback history only (ED 3).
    scrollback = 3,
    _,
};

pub fn eraseDisplay(self: *Grid, allocator: std.mem.Allocator, mode: EraseMode) !void {
    // Nothing has been stored yet, so everything is already blank.
    if (self.rows.items.len == 0) return;

    const cols = self.rows_width;
    const first_live = self.firstLive();
    const cur = first_live + @min(self.cursor_y, self.visable_rows -| 1);

    switch (mode) {
        .to_end => {
            self.eraseCells(cur, self.cursor_x, cols);
            for (cur + 1..self.rows.items.len) |r| self.eraseCells(r, 0, cols);
        },
        .to_start => {
            for (first_live..cur) |r| self.eraseCells(r, 0, cols);
            self.eraseCells(cur, 0, self.cursor_x + 1);
        },
        .all => {
            for (first_live..self.rows.items.len) |r| self.eraseCells(r, 0, cols);
        },
        .scrollback => {
            if (first_live > 0) {
                self.dropOldestRows(allocator, first_live);
            }
            self.scroll_offset = 0;
        },
        _ => {},
    }
}

pub fn eraseLine(self: *Grid, allocator: std.mem.Allocator, mode: usize) !void {
    _ = allocator; // erasing never allocates; kept so call sites don't change
    if (self.rows.items.len == 0) return;

    const row = self.liveRowIndex();
    switch (mode) {
        0 => self.eraseCells(row, self.cursor_x, self.rows_width),
        1 => self.eraseCells(row, 0, self.cursor_x + 1),
        2 => self.eraseCells(row, 0, self.rows_width),
        else => {},
    }
}

/// CSI N P — Delete Character (DCH).
///
/// Deletes `n` characters starting at the cursor column.
/// Characters to the right of the deleted region are shifted left to fill
/// the gap. The `n` vacated cells at the right end of the line are filled
/// with blank (default) cells. The cursor position does not change.
///
/// Standard reference: ECMA-48 §8.3.26
pub fn deleteChars(self: *Grid, allocator: std.mem.Allocator, n: usize) !void {
    _ = allocator; // never allocates; kept so call sites don't change
    if (self.rows.items.len == 0) return;

    const cols = self.rows_width;
    const col = self.cursor_x;
    if (col >= cols) return;

    const row_index = self.liveRowIndex();
    if (row_index >= self.rows.items.len) return;

    // Deleting more chars than remain on the line is equivalent to erasing
    // from the cursor to the end of the line.
    const count = @min(n, cols - col);
    if (count == 0) return;

    const cells = self.rows.items[row_index].cells;
    const tail = cols - col - count; // cells that slide left
    if (tail > 0) {
        std.mem.copyForwards(Cell, cells[col..][0..tail], cells[col + count ..][0..tail]);
    }
    @memset(cells[col + tail .. cols], Cell.default);
}

pub const CursorPos = struct { x: usize, y: usize };

pub fn cursorPos(self: *const Grid) CursorPos {
    return .{ .x = self.cursor_x, .y = self.cursor_y };
}

/// Set the scrolling region using 0-based, inclusive live-screen rows.
/// Invalid or single-line regions fall back to the full screen.
pub fn setScrollRegion(self: *Grid, top: usize, bottom: usize) void {
    if (self.visable_rows == 0) return;

    const max = self.visable_rows - 1;
    const t = @min(top, max);
    const b = @min(bottom, max);

    if (b <= t) {
        self.scroll_top = 0;
        self.scroll_bottom = max;
    } else {
        self.scroll_top = t;
        self.scroll_bottom = b;
    }

    // DECSTBM homes the cursor.
    self.cursor_x = 0;
    self.cursor_y = 0;
    self.wrap_pending = false;
}

/// Scroll the active region up by `n` rows. A full-screen scroll also feeds
/// scrollback; a sub-region scroll only moves rows inside the region.
pub fn scrollRegionUp(self: *Grid, allocator: std.mem.Allocator, n: usize) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    const region = self.scrollRegionBounds();
    const count = region.bottom - region.top + 1;
    const shift = @min(n, count);
    if (shift == 0) return;

    if (self.isFullScrollRegion() and shift < self.visable_rows) {
        for (0..shift) |_| try self.pushRow(allocator);
        return;
    }

    self.scrollRowsUp(region.top, region.bottom, shift);
}

/// Scroll the active region down by `n` rows. This never feeds scrollback.
pub fn scrollRegionDown(self: *Grid, allocator: std.mem.Allocator, n: usize) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    const region = self.scrollRegionBounds();
    const count = region.bottom - region.top + 1;
    const shift = @min(n, count);
    if (shift == 0) return;

    self.scrollRowsDown(region.top, region.bottom, shift);
}

/// CSI M — Delete Line. Lines below the cursor inside the scroll region move up.
pub fn deleteLines(self: *Grid, allocator: std.mem.Allocator, n: usize) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    const region = self.scrollRegionBounds();
    if (self.cursor_y < region.top or self.cursor_y > region.bottom) return;

    const count = region.bottom - self.cursor_y + 1;
    const shift = @min(n, count);
    if (shift == 0) return;

    self.scrollRowsUp(self.cursor_y, region.bottom, shift);
}

/// CSI L — Insert Line. Lines from the cursor down move down inside the region.
pub fn insertLines(self: *Grid, allocator: std.mem.Allocator, n: usize) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    const region = self.scrollRegionBounds();
    if (self.cursor_y < region.top or self.cursor_y > region.bottom) return;

    const count = region.bottom - self.cursor_y + 1;
    const shift = @min(n, count);
    if (shift == 0) return;

    self.scrollRowsDown(self.cursor_y, region.bottom, shift);
}

/// CSI X — Erase Character(s). Blanks cells without moving the cursor.
pub fn eraseChars(self: *Grid, n: usize) void {
    if (self.rows.items.len == 0 or self.rows_width == 0) return;

    const row_index = self.liveRowIndex();
    if (row_index >= self.rows.items.len) return;

    const end = @min(self.cursor_x +| n, self.rows_width);
    if (self.cursor_x >= end) return;

    @memset(self.rows.items[row_index].cells[self.cursor_x..end], Cell.default);
}

/// CSI @ — Insert Character(s). Shifts the rest of the line to the right.
pub fn insertChars(self: *Grid, n: usize) void {
    if (self.rows.items.len == 0 or self.rows_width == 0) return;

    const row_index = self.liveRowIndex();
    if (row_index >= self.rows.items.len) return;

    const col = self.cursor_x;
    if (col >= self.rows_width) return;

    const count = @min(n, self.rows_width - col);
    if (count == 0) return;

    const cells = self.rows.items[row_index].cells;
    std.mem.copyBackwards(Cell, cells[col + count ..], cells[col .. self.rows_width - count]);
    @memset(cells[col .. col + count], Cell.default);
}

/// ESC M — Reverse Index. Moves up one line, scrolling the region down when
/// already at the top margin.
pub fn reverseIndex(self: *Grid, allocator: std.mem.Allocator) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    self.wrap_pending = false;
    const region = self.scrollRegionBounds();

    if (self.cursor_y == region.top) {
        try self.scrollRegionDown(allocator, 1);
        self.cursor_y = region.top;
    } else if (self.cursor_y > 0) {
        self.cursor_y -= 1;
    }
}

pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
    for (self.rows.items) |row| allocator.free(row.cells);
    self.rows.deinit(allocator);
    self.rows = .empty;

    self.scroll_offset = 0;
    self.wrap_pending = false;
}

// ---------------------------------------------------------------------------
// Reading (rendering)
// ---------------------------------------------------------------------------

pub const Iterator = struct {
    grid: *const Grid,
    current_x: usize = 0,
    current_y: usize = 0,

    row: ?Row = null,

    pub const Item = struct {
        x: usize,
        y: usize,
        cell: Cell,
    };

    pub fn next(self: *Iterator) ?Item {
        const g = self.grid;

        if (g.rows_width == 0 or self.current_y >= g.visable_rows)
            return null;

        const x = self.current_x;
        const y = self.current_y;

        if (x == 0)
            self.row = g.visibleRow(y);

        const cell: Cell = if (self.row) |r|
            r.cells[x]
        else
            Cell.default;

        self.current_x += 1;

        if (self.current_x >= g.rows_width) {
            self.current_x = 0;
            self.current_y += 1;
        }

        return .{
            .x = x,
            .y = y,
            .cell = cell,
        };
    }
};

pub fn iterator(self: *const Grid) Iterator {
    return .{ .grid = self };
}

/// Write the background color of every visible cell into `colors` as
/// packed RGBA8 texels in row-major order (`rows * cols * 4` bytes).
/// `colors.len` must be exactly `visable_rows * rows_width * 4`.
pub fn fillBackgroundColors(self: *const Grid, colors: []u8) void {
    const cols = self.rows_width;
    const rows = self.visable_rows;
    std.debug.assert(colors.len == rows * cols * 4);

    const blank_bg = self.bg_color;
    for (0..rows) |y| {
        const out = colors[y * cols * 4 ..][0 .. cols * 4];
        if (self.visibleRow(y)) |row| {
            // The cursor block never changes a cell's background, so it can be
            // ignored here (see `Iterator.next`).
            for (row.cells, 0..) |cell, x| {
                const bg: color.RGBA = if (cell.unicode == 0) blank_bg else cell.bg_color;
                @memcpy(out[x * 4 ..][0..4], std.mem.asBytes(&bg));
            }
        } else {
            for (0..cols) |x| @memcpy(out[x * 4 ..][0..4], std.mem.asBytes(&blank_bg));
        }
    }
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
