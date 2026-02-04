const Cache = @This();

occupation_map: OccupationHashMap,

pub const InitError = std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator) InitError!Cache {
    const map = OccupationHashMap.init(allocator);

    try map.ensureTotalCapacity(1024);

    return .{
        .occupation_map = map,
    };
}

const std = @import("std");
const root = @import("root.zig");

const Context = struct {
    pub fn hash(_: @This(), k: root.GlyphID) u32 {
        return k.index ^ k.font;
    }

    pub fn eql(_: @This(), a: root.GlyphID, b: root.GlyphID, _: usize) bool {
        return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    }
};
const OccupationHashMap = std.array_hash_map.ArrayHashMapWithAllocator(root.GlyphID, root.GlyphAtlasEntry, Context, false);
