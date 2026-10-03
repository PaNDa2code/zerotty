//! Terminal cell grid: the live screen plus a bounded scrollback history.
//!
//! ## Memory layout
//!
//! Every row lives in ONE flat allocation (`cells`, `cap_rows * rows_width`
//! cells) that is used as a ring of rows, plus one soft-wrap flag per row.
//!
//!   logical row:   0 ............ row_count - visable_rows ......... row_count - 1
//!                  [ oldest ]      [        scrollback        ][  live screen  ]
//!
//! Logical row 0 is the oldest row still kept and the last `visable_rows`
//! logical rows are the live screen. A logical row maps to a ring slot with
//! `(head + logical) % cap_rows`.
//!
//! Consequences:
//!   * A row is a plain slice into contiguous memory: no per-row allocation,
//!     no pointer chasing, no per-row capacity slack.
//!   * Scrolling is O(1). Once the ring is full, the oldest row is blanked and
//!     recycled as the new bottom row; nothing is allocated, copied or shifted.
//!   * Scrollback is bounded by `max_scrollback` rows.
//!   * The ring grows geometrically (amortised O(1) per row) until it reaches
//!     its limit, so a mostly-idle terminal never pays for the full scrollback.
//!   * The hot paths (`putChar`, `linefeed`, erase, `deleteChars`) never allocate
//!     except when the ring grows.
//!
//! Every row is always exactly `rows_width` cells wide; a blank cell is
//! `Cell.default` (`unicode == 0`).

const std = @import("std");
const Grid = @This();
const Row = @import("Row.zig");
const grid = @import("root.zig");
const Cell = grid.Cell;
const color = @import("zerotty").terminal.color;

/// Flat ring storage: `cap_rows` rows of `rows_width` cells each.
/// Only the first `row_count` logical rows hold meaningful data.
cells: []Cell = &.{},
/// Soft-wrap flag per ring slot (parallel to the rows in `cells`).
wrapped: []bool = &.{},
/// Rows the ring has room for.
cap_rows: usize = 0,
/// Ring slot of logical row 0 (the oldest row). Non-zero only once the ring is
/// full and has started recycling rows.
head: usize = 0,
/// Rows currently stored: scrollback + live screen. `0` until first use.
row_count: usize = 0,

/// Viewport height in rows.
visable_rows: usize,
/// Viewport width in columns. Change it through `resizeVisable`, not directly.
rows_width: usize,

/// Maximum number of history rows kept above the live screen. Set this at
/// construction; lowering it later only takes effect lazily.
max_scrollback: usize = 10_000,

scroll_offset: usize = 0,

// Background used for blank (never-written/erased) cells.
bg_color: color.RGBA = .black,

cursor_x: usize = 0,
cursor_y: usize = 0,

show_cursor: bool = true,

cursor_unicode: u32 = eighth_block, // or vertical_bar

pub const eighth_block = 0x258F;
pub const full_block = 0x2588;
pub const lower_eighth_block = 0x2581;
pub const vertical_bar = 0x2502;
// ---------------------------------------------------------------------------
// Ring helpers
// ---------------------------------------------------------------------------

/// Ring slot of a logical row (0 = oldest).
inline fn physIndex(self: *const Grid, logical: usize) usize {
    const p = self.head + logical;
    return if (p >= self.cap_rows) p - self.cap_rows else p;
}

inline fn slotCells(self: *const Grid, slot: usize) []Cell {
    return self.cells[slot * self.rows_width ..][0..self.rows_width];
}

/// Logical index of the first live-screen row.
inline fn firstLive(self: *const Grid) usize {
    return self.row_count -| self.visable_rows;
}

/// Ring slot of live-screen row `y` (0 = top of the live screen).
inline fn liveSlot(self: *const Grid, y: usize) usize {
    std.debug.assert(y < self.visable_rows);
    return self.physIndex(self.firstLive() + y);
}

fn blankSlot(self: *Grid, slot: usize) void {
    @memset(self.slotCells(slot), Cell.default);
    self.wrapped[slot] = false;
}

/// Rebuild the ring into a fresh allocation. This is the only place that
/// (re)allocates storage, and it is used for first-time setup, geometric
/// growth, width changes and clearing scrollback.
///
/// * `new_cols`: width of the new rows (cells are truncated / blank-padded).
/// * `new_cap`:  ring capacity in rows; must be >= the resulting row count.
/// * `skip`:     drop this many of the OLDEST rows.
/// * `extra`:    append this many blank rows at the bottom.
///
/// On error the grid is left untouched. On success `head == 0`.
fn relayout(
    self: *Grid,
    allocator: std.mem.Allocator,
    new_cols: usize,
    new_cap: usize,
    skip: usize,
    extra: usize,
) !void {
    std.debug.assert(new_cols > 0);
    std.debug.assert(skip <= self.row_count);
    const kept = self.row_count - skip;
    const new_count = kept + extra;
    std.debug.assert(new_cap >= new_count);

    const total = std.math.mul(usize, new_cap, new_cols) catch return error.OutOfMemory;
    const new_cells = try allocator.alloc(Cell, total);
    errdefer allocator.free(new_cells);
    const new_wrapped = try allocator.alloc(bool, new_cap);

    const old_cols = self.rows_width;
    const copy_cols = @min(old_cols, new_cols);
    for (0..kept) |i| {
        const src_slot = self.physIndex(skip + i);
        const src = self.cells[src_slot * old_cols ..][0..old_cols];
        const dst = new_cells[i * new_cols ..][0..new_cols];
        @memcpy(dst[0..copy_cols], src[0..copy_cols]);
        // Truncated cells are simply dropped. A fuller implementation would
        // reflow them into a continuation row (see `Row.wrapped`).
        @memset(dst[copy_cols..], Cell.default);
        new_wrapped[i] = self.wrapped[src_slot];
    }
    for (kept..new_count) |i| {
        @memset(new_cells[i * new_cols ..][0..new_cols], Cell.default);
        new_wrapped[i] = false;
    }
    // Slots in [new_count, new_cap) stay uninitialised on purpose: they are
    // never read, and `pushRow` blanks a slot when it becomes live.

    allocator.free(self.cells);
    allocator.free(self.wrapped);
    self.cells = new_cells;
    self.wrapped = new_wrapped;
    self.cap_rows = new_cap;
    self.head = 0;
    self.row_count = new_count;
}

/// Grow the ring's capacity with `realloc`. Only valid while the ring has not
/// wrapped (`head == 0`), which is always the case while it is still growing, so
/// the allocator can usually extend the block in place (no copy, no second
/// buffer alive at the same time). Rows are unchanged.
fn growInPlace(self: *Grid, allocator: std.mem.Allocator, new_cap: usize) !void {
    std.debug.assert(self.head == 0 and new_cap >= self.cap_rows);
    const total = std.math.mul(usize, new_cap, self.rows_width) catch return error.OutOfMemory;
    // If the second call fails, `wrapped` is merely longer than `cap_rows`
    // needs, which is harmless.
    self.wrapped = try allocator.realloc(self.wrapped, new_cap);
    self.cells = try allocator.realloc(self.cells, total);
    self.cap_rows = new_cap;
}

/// Ensure the live screen exists (`row_count >= visable_rows`). Cheap no-op
/// after first use, so it is safe to call unconditionally.
inline fn ensureLiveRows(self: *Grid, allocator: std.mem.Allocator) !void {
    if (self.row_count < self.visable_rows) try self.materialize(allocator);
}

fn materialize(self: *Grid, allocator: std.mem.Allocator) !void {
    @branchHint(.cold);
    try self.relayout(allocator, self.rows_width, self.visable_rows, 0, self.visable_rows - self.row_count);
}

/// Add a blank row at the bottom of the buffer, scrolling the live screen.
/// Recycles the oldest row once the ring is full. Keeps the viewport anchored
/// on the same content if the user is scrolled back into history.
fn pushRow(self: *Grid, allocator: std.mem.Allocator) !void {
    const max_rows = self.visable_rows +| self.max_scrollback;

    if (self.cap_rows > max_rows) {
        // The limit dropped since the ring was allocated (the viewport shrank or
        // `max_scrollback` was lowered): trim to it so the ring can be full again.
        @branchHint(.cold);
        try self.relayout(allocator, self.rows_width, max_rows, self.row_count -| max_rows, 0);
    }

    if (self.row_count == self.cap_rows) {
        if (self.cap_rows < max_rows) {
            @branchHint(.unlikely);
            const grown = @min(max_rows, @max(self.cap_rows * 2, 64));
            if (self.head == 0) {
                try self.growInPlace(allocator, grown);
            } else {
                try self.relayout(allocator, self.rows_width, grown, 0, 0);
            }
        }
    }

    if (self.row_count < self.cap_rows) {
        self.blankSlot(self.physIndex(self.row_count));
        self.row_count += 1;
        if (self.scroll_offset > 0) self.scroll_offset += 1;
    } else {
        // Ring is full: the oldest row becomes the new bottom row.
        const slot = self.head;
        self.blankSlot(slot);
        self.head = if (slot + 1 == self.cap_rows) 0 else slot + 1;
        // The oldest row just fell off the top, so a scrolled-back view shifts
        // by one to stay on the same content (until it hits the oldest row).
        if (self.scroll_offset > 0)
            self.scroll_offset = @min(self.scroll_offset + 1, self.maxScrollOffset());
    }
}

// ---------------------------------------------------------------------------
// Viewport
// ---------------------------------------------------------------------------

/// Resize the visible viewport.
///
/// * Width: every stored row (scrollback included) is truncated or blank-padded.
/// * Height, shrinking: the top rows of the old screen move into scrollback.
/// * Height, growing: rows are pulled back out of scrollback first (the cursor
///   moves down with them so it stays on the same content); blank rows are
///   appended only if scrollback runs out.
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

    var cursor_y = self.cursor_y;

    if (self.row_count != 0) {
        var extra: usize = 0;
        if (visable_rows > self.visable_rows) {
            const grow = visable_rows - self.visable_rows;
            const scrollback = self.row_count - self.visable_rows;
            const pull = @min(grow, scrollback);
            cursor_y += pull;
            extra = grow - pull;
        }
        // Shrinking the screen pushes rows into scrollback, which can exceed
        // the limit; drop the oldest rows in that case.
        const skip = (self.row_count + extra) -| (visable_rows +| self.max_scrollback);

        if (rows_width != self.rows_width or skip > 0 or extra > 0) {
            try self.relayout(allocator, rows_width, self.row_count - skip + extra, skip, extra);
        }
    }

    self.visable_rows = visable_rows;
    self.rows_width = rows_width;
    self.cursor_y = @min(cursor_y, visable_rows - 1);
    self.cursor_x = @min(self.cursor_x, rows_width - 1);
    self.clampScrollOffset();

    try self.ensureLiveRows(allocator);
}

/// Total rows currently stored (scrollback + live screen).
pub fn rowCount(self: *const Grid) usize {
    return self.row_count;
}

/// How many rows back into history the viewport is currently allowed
/// to scroll (0 if there's no scrollback beyond the visible area).
pub fn maxScrollOffset(self: *const Grid) usize {
    return self.row_count -| self.visable_rows;
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
    if (y >= self.visable_rows or self.row_count < self.visable_rows) return null;
    const offset = @min(self.scroll_offset, self.maxScrollOffset());
    const slot = self.physIndex(self.row_count - self.visable_rows - offset + y);
    return .{ .cells = self.slotCells(slot), .wrapped = self.wrapped[slot] };
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// Write a cell at the cursor position and advance the cursor,
/// wrapping to the next line if we hit the right edge.
pub fn putChar(self: *Grid, allocator: std.mem.Allocator, cell: Cell) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    if (self.cursor_x >= self.rows_width) {
        // Only reachable if the caller moved the cursor past the edge by hand.
        self.wrapped[self.liveSlot(self.cursor_y)] = true;
        try self.linefeed(allocator);
        self.cursor_x = 0;
    }

    const slot = self.liveSlot(self.cursor_y);
    self.slotCells(slot)[self.cursor_x] = cell;

    self.cursor_x += 1;
    if (self.cursor_x >= self.rows_width) {
        self.wrapped[slot] = true;
        try self.linefeed(allocator);
        self.cursor_x = 0;
    }
}

/// Move the cursor down one line, scrolling the live area
/// (appending a fresh blank row) if we're already at the bottom.
pub fn linefeed(self: *Grid, allocator: std.mem.Allocator) !void {
    if (self.rows_width == 0 or self.visable_rows == 0) return;
    try self.ensureLiveRows(allocator);

    if (self.cursor_y + 1 < self.visable_rows) {
        self.cursor_y += 1;
        return;
    }
    self.cursor_y = self.visable_rows - 1;
    try self.pushRow(allocator);
}

/// Move cursor to column 0 of the current line.
pub fn carriageReturn(self: *Grid) void {
    self.cursor_x = 0;
}

// ---------------------------------------------------------------------------
// Erasing
// ---------------------------------------------------------------------------

/// Blank columns `[start_col, end_col)` of a logical row. Cannot fail.
fn eraseCells(self: *Grid, logical: usize, start_col: usize, end_col: usize) void {
    const cols = self.rows_width;
    const end = @min(end_col, cols);
    const start = @min(start_col, end);
    const slot = self.physIndex(logical);
    @memset(self.slotCells(slot)[start..end], Cell.default);
    if (start == 0 and end == cols) self.wrapped[slot] = false;
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
    if (self.row_count == 0) return;

    const cols = self.rows_width;
    const first_live = self.firstLive();
    const cur = first_live + self.cursor_y;

    switch (mode) {
        .to_end => {
            self.eraseCells(cur, self.cursor_x, cols);
            for (cur + 1..self.row_count) |r| self.eraseCells(r, 0, cols);
        },
        .to_start => {
            for (first_live..cur) |r| self.eraseCells(r, 0, cols);
            self.eraseCells(cur, 0, self.cursor_x + 1);
        },
        .all => {
            for (first_live..self.row_count) |r| self.eraseCells(r, 0, cols);
        },
        .scrollback => {
            const scrollback = first_live;
            if (scrollback > 0) {
                // Compact into a live-screen-sized allocation to give the
                // memory back. If that allocation fails, still drop the
                // history by just moving the ring head (O(1), can't fail).
                self.relayout(allocator, cols, self.visable_rows, scrollback, 0) catch {
                    self.head = self.physIndex(scrollback);
                    self.row_count = self.visable_rows;
                };
            }
            self.scroll_offset = 0;
        },
        _ => {},
    }
}

pub fn eraseLine(self: *Grid, allocator: std.mem.Allocator, mode: usize) !void {
    _ = allocator; // erasing never allocates; kept so call sites don't change
    if (self.row_count == 0) return;
    const row = self.firstLive() + self.cursor_y;
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
    if (self.row_count == 0) return;

    const cols = self.rows_width;
    const col = self.cursor_x;
    if (col >= cols) return;

    // Deleting more chars than remain on the line is equivalent to erasing
    // from the cursor to the end of the line.
    const count = @min(n, cols - col);
    if (count == 0) return;

    const cells = self.slotCells(self.liveSlot(self.cursor_y));
    const tail = cols - col - count; // cells that slide left
    if (tail > 0) {
        std.mem.copyForwards(Cell, cells[col..][0..tail], cells[col + count ..][0..tail]);
    }
    @memset(cells[col + tail .. cols], Cell.default);
}

pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
    allocator.free(self.cells);
    allocator.free(self.wrapped);
    self.cells = &.{};
    self.wrapped = &.{};
    self.cap_rows = 0;
    self.head = 0;
    self.row_count = 0;
}

// ---------------------------------------------------------------------------
// Reading (rendering)
// ---------------------------------------------------------------------------

pub const Iterator = struct {
    grid: *const Grid,
    current_x: usize = 0,
    current_y: usize = 0,

    row: ?Row = null,

    pending_cursor: ?Item = null,

    pub const Item = struct {
        x: usize,
        y: usize,
        cell: Cell,
        cursor: bool = false,
    };

    pub fn next(self: *Iterator) ?Item {
        const g = self.grid;

        // Return the cursor item that was queued by the
        // previous normal-cell iteration.
        if (self.pending_cursor) |item| {
            self.pending_cursor = null;
            return item;
        }

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

        if (g.show_cursor and g.cursor_x == x and g.cursor_y == y) {
            // Inherit the cell's entire style.
            var cursor_cell = cell;

            // Only change what visually represents the cursor.
            cursor_cell.unicode = g.cursor_unicode;

            self.pending_cursor = .{
                .x = x,
                .y = y,
                .cell = cursor_cell,
                .cursor = true,
            };
        }

        return .{
            .x = x,
            .y = y,
            .cell = cell,
            .cursor = false,
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
