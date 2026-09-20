//! Read-only view of a single row of a `Grid`.
//!
//! A `Row` does not own its cells: it points into the grid's flat storage and
//! is only valid until the next call that mutates or resizes the grid.
const Cell = @import("root.zig").Cell;
const Row = @This();

/// Exactly `Grid.rows_width` cells.
cells: []const Cell,

/// True if this row was filled to the right edge and the text continued on the
/// next row (a soft wrap, as opposed to a hard line break).
wrapped: bool,

pub fn len(self: Row) usize {
    return self.cells.len;
}
