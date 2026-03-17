const Cache = @This();

allocator: std.mem.Allocator,

packers: std.ArrayList(Packer),
map: CacheHashMap,

// this will be used for uploading to GPU textures.
new_added_entries: std.ArrayList(root.GlyphAtlasEntry),

pub fn init(allocator: std.mem.Allocator) Cache {
    return .{
        .allocator = allocator,
        .packers = .empty,
        .map = .empty,
        .new_added_entries = .empty,
    };
}

pub fn deinit(self: *Cache) void {
    for (self.packers.items) |*packer| {
        packer.deinit(self.allocator);
    }
    self.packers.deinit(self.allocator);
    self.map.deinit(self.allocator);
}

pub fn getAtlasEntry(self: *const Cache, glyph_id: root.GlyphID) ?root.GlyphAtlasEntry {
    return self.map.get(glyph_id);
}

pub fn pushEntry(
    self: *Cache,
    glyph_id: root.GlyphID,
    width: u8,
    height: u8,
    x_bearing: i8,
    y_bearing: i8,
    new_atlas: *bool,
) !root.GlyphAtlasEntry {
    new_atlas.* = false;

    if (self.map.get(glyph_id)) |entry|
        return entry;

    for (self.packers.items, 0..) |*packer, i| {
        const position = try packer.findEmptyRectangle(
            self.allocator,
            @intCast(height),
            @intCast(width),
        ) orelse continue;

        const entry = root.GlyphAtlasEntry{
            .atlas_id = @intCast(i),
            .x = @intCast(position.x),
            .y = @intCast(position.y),

            .width = width,
            .height = height,

            .x_bearing = x_bearing,
            .y_bearing = y_bearing,
        };

        try self.map.put(self.allocator, glyph_id, entry);

        return entry;
    }

    new_atlas.* = true;

    try self.packers.append(
        self.allocator,
        Packer.init(root.max_atlas_dim, root.max_atlas_dim),
    );

    const atlas_index = self.packers.items.len - 1;

    const position = try self.packers.items[atlas_index].findEmptyRectangle(
        self.allocator,
        @intCast(height),
        @intCast(width),
    ) orelse unreachable;

    const entry = root.GlyphAtlasEntry{
        .atlas_id = @intCast(atlas_index),
        .x = @intCast(position.x),
        .y = @intCast(position.y),

        .width = width,
        .height = height,

        .x_bearing = x_bearing,
        .y_bearing = y_bearing,
    };

    try self.map.put(self.allocator, glyph_id, entry);

    return entry;
}

const std = @import("std");
const root = @import("root.zig");
const bin_packing = @import("bin_packing.zig");
const Packer = bin_packing.Packer;

const CacheHashMapContext = struct {
    pub fn hash(_: @This(), k: root.GlyphID) u64 {
        return @bitCast(k);
    }

    pub fn eql(_: @This(), a: root.GlyphID, b: root.GlyphID) bool {
        return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    }
};
const CacheHashMap = std.hash_map.HashMapUnmanaged(root.GlyphID, root.GlyphAtlasEntry, CacheHashMapContext, 80);

test Cache {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    for (0..100_000) |_| {
        var rand = std.Random.DefaultPrng.init(0);
        const width = std.Random.limitRangeBiased(u64, rand.next(), std.math.maxInt(u8));
        const height = std.Random.limitRangeBiased(u64, rand.next(), std.math.maxInt(u8));
        const x_bearing = std.Random.limitRangeBiased(u64, rand.next(), std.math.maxInt(i8));
        const y_bearing = std.Random.limitRangeBiased(u64, rand.next(), std.math.maxInt(i8));
        const glyph_id = rand.next();
        var new_atlas = false;

        _ = try cache.pushEntry(
            @bitCast(glyph_id),
            @intCast(width),
            @intCast(height),
            @intCast(x_bearing),
            @intCast(y_bearing),
            &new_atlas,
        );
    }
}
