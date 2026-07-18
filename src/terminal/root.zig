pub const color = @import("color.zig");
pub const grid = @import("grid/root.zig");

pub const ScrollBack = @import("Scrollback.zig");
pub const Terminal = @import("Terminal.zig");

comptime {
    @import("std").testing.refAllDecls(@This());
}
