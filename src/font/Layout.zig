const Layout = @This();

allocator: std.mem.Allocator,
graph: Graphmes,

pub const ClusterIterator = struct {
    graph_cluster_iter: Graphmes.Iterator,

    pub fn next(self: *ClusterIterator) ?Graphmes.Grapheme {
        return self.graph_cluster_iter.next();
    }
};

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Layout {
    return .{
        .allocator = allocator,
        .graph = try .init(allocator),
    };
}

pub fn deinit(self: *Layout) void {
    self.graph.deinit(self.allocator);
}

pub fn iterator(self: *Layout, utf8: []const u8) ClusterIterator {
    return .{
        .layout = self,
        .graph_cluster_iter = self.graph.iterator(utf8),
    };
}

const std = @import("std");
const root = @import("root.zig");
const Graphmes = @import("Graphemes");
