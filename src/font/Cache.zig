const Cache = @This();

allocator: std.mem.Allocator,

packers: std.ArrayList(Packer),
map: CacheHashMap,

pub fn init(allocator: std.mem.Allocator) Cache {
    return .{
        .allocator = allocator,
        .packers = .empty,
        .map = .empty,
    };
}

pub fn deinit(self: *Cache) void {
    for (self.packers.items) |*packer| {
        packer.deinit(self.allocator);
    }
    self.packers.deinit(self.allocator);
    self.map.deinit(self.allocator);
}

const std = @import("std");
const root = @import("root.zig");
const bin_packing = @import("bin_packing.zig");
const Packer = bin_packing.Packer;

const CacheHashMapContext = struct {
    pub fn hash(_: @This(), k: root.GlyphID) u64 {
        return @bitCast(k);
    }

    pub fn eql(_: @This(), a: root.GlyphID, b: root.GlyphID, _: usize) bool {
        return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    }
};
const CacheHashMap = std.hash_map.HashMapUnmanaged(root.GlyphID, root.GlyphAtlasEntry, CacheHashMapContext, 80);
