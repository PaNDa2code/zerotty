const std = @import("std");
const color = @import("zerotty").terminal.color;

pub const Grid = @import("Grid.zig");
pub const Row = @import("Row.zig");

pub const Cell = struct {
    unicode: u32,
    fg_color: color.RGBA,
    bg_color: color.RGBA,
    flags: color.ansi.Flags,

    pub const default = Cell{
        .unicode = 0,
        .fg_color = .white,
        .bg_color = .black,
        .flags = .{},
    };
};

comptime {
    _ = @import("tests.zig");
}
