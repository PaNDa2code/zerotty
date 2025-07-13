pub const Atlas = @import("Atlas.zig");

test Atlas {
    const std = @import("std");
    const allocator = std.testing.allocator;

    var atlas = try Atlas.create(
        allocator,
        10,
        10,
        0,
        128,
    );
    defer atlas.deinit(allocator);

    try Atlas.saveAtlasAsPGM("atlas.PGM", atlas.buffer, atlas.width, atlas.height);
}
