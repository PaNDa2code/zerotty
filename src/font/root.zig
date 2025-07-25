pub const Atlas = @import("Atlas.zig");

test Atlas {
    const std = @import("std");
    const allocator = std.testing.allocator;

    var atlas = try Atlas.create(
        allocator,
        30,
        20,
        0,
        128,
    );
    defer atlas.deinit(allocator);

    try Atlas.saveAtlas(std.testing.allocator,"temp/atlas.png", atlas.buffer, atlas.width, atlas.height);
}
