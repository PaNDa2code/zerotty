const AssetsManager = @This();

pub var instance: AssetsManager = undefined;

pub const assets_archive = @embedFile("assets.tar.zst");

compressed_data: []const u8,

decompress_buffer: []u8 = undefined,
zstd_decompress: zstd.Decompress = undefined,
tar_iter: tar.Iterator = undefined,

pub fn init(allocator: std.mem.Allocator, compressed_data: []const u8) !AssetsManager {
    return .{
        .compressed_data = compressed_data,
        .decompress_buffer = try allocator.alloc(u8, zstd.default_window_len),
    };
}

pub fn deinit(self: *AssetsManager, allocator: std.mem.Allocator) void {
    allocator.free(self.decompress_buffer);
}

fn decompressReset(self: *AssetsManager) void {
    var fixed_reader = std.Io.Reader.fixed(self.compressed_data);
    self.zstd_decompress = zstd.Decompress.init(&fixed_reader, self.decompress_buffer[0..], .{});
}

fn tarReset(self: *AssetsManager) void {
    self.tar_iter = tar.Iterator.init(&self.zstd_decompress.reader, .{});
}

pub fn get(self: *AssetsManager, name: []const u8, writer: *std.Io.Writer) !void {
    self.decompressReset();
    self.tarReset();

    while (try self.tar_iter.next()) |file| {
        if (!std.mem.eql(u8, name, file.name)) continue;

        return self.tar_iter.streamRemaining(file, writer);
    }

    return error.NotFound;
}

pub fn getAlloc(self: *AssetsManager, allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    self.decompressReset();
    self.tarReset();

    while (try self.tar_iter.next()) |file| {
        if (!std.mem.eql(u8, name, file.name)) continue;

        const buffer = try allocator.alloc(u8, file.size);
        var writer = std.Io.Writer.fixed(buffer);

        try self.tar_iter.streamRemaining(file, &writer);

        return buffer;
    }

    return error.NotFound;
}

const std = @import("std");
const tar = std.tar;
const zstd = std.compress.zstd;
