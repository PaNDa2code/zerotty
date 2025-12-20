const Scrollback = @This();

const CircularArray = @import("circular_array.zig").CircularArray;
const Grid = @import("Grid.zig");
const Cell = Grid.Cell;

cells: CircularArray(Cell),

