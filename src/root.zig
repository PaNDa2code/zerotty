// top level zerotty module

pub const system = @import("system/root.zig");
pub const renderer = @import("renderer/root.zig");
pub const terminal = @import("terminal/root.zig");
pub const font = @import("font/root.zig");
pub const math = @import("renderer/common/math.zig");
pub const AssetsManager = @import("AssetsManager.zig");
pub const assets = @import("assets");

comptime {
    @import("std").testing.refAllDecls(@This());
}
