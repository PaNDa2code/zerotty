pub const Atlas = @import("Atlas.zig");

test Atlas {
    const std = @import("std");
    const allocator = std.testing.allocator;

    var atlas = try Atlas.create(
        allocator,
        30,
        20,
        0x2500,
        0x257F,
    );
    defer atlas.deinit(allocator);
}
