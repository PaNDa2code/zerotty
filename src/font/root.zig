pub const Atlas = @import("Atlas.zig");

test Atlas {
    const std = @import("std");
    const allocator = std.testing.allocator;

    const altas = try Atlas.create(
        allocator,
        10,
        10,
        0,
        128,
    );
    defer altas.deinit(allocator);
}
