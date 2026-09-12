const AssetsManager = @This();

pub var instance: AssetsManager = undefined;

pub const assets_archive = @embedFile("assets.tar.zst");
pub const assets_tar = @embedFile("assets.tar");

pub const Asset = struct {
    reader: std.Io.Reader,
    size: usize,

    pub const FixedBufferError = error{
        AssetReaderNotFixed,
    };

    /// this returns a refrance slice to file bytes from the main **AssetsManager** memory,
    /// the buffer is alive until you call `.deinit()` on the **AssetsManager**
    pub fn fixedBuffer(asset: Asset) FixedBufferError![]const u8 {
        if (asset.reader.end != asset.size)
            return error.AssetReaderNotFixed;

        return asset.reader.buffer[0..asset.size];
    }

    pub fn allocBuffer(asset: Asset, allocator: std.mem.Allocator) ![]const u8 {
        const buffer = try allocator.alloc(u8, asset.size);
        try asset.reader.readSliceAll(buffer);

        return buffer;
    }
};

tar_data: []const u8,
allocator: ?std.mem.Allocator = null,

pub fn decompressAndInit(allocator: std.mem.Allocator, compressed_data: []const u8) !AssetsManager {
    var writer: std.Io.Writer.Allocating = try .initCapacity(allocator, 1024 * 1024 * 8);
    errdefer writer.deinit();

    var reader: std.Io.Reader = .fixed(compressed_data);
    var zstd_decompress: zstd.Decompress = .init(&reader, &.{}, .{});
    _ = try zstd_decompress.reader.streamRemaining(&writer.writer);

    return .{
        .tar_data = try writer.toOwnedSlice(),
        .allocator = allocator,
    };
}

pub fn initFromTar(tar_data: []const u8) AssetsManager {
    return .{
        .tar_data = tar_data,
    };
}

pub fn deinit(self: *AssetsManager) void {
    if (self.allocator) |alloc|
        alloc.free(self.tar_data);
}

fn matchesName(name: []const u8, file_name: []const u8) bool {
    if (file_name.len == 0) return false;

    var entry = file_name;
    while (entry[0] == '.' and entry.len > 1 and entry[1] == '/') {
        entry = entry[2..];
    }
    while (entry.len != 0 and entry[0] == '/') {
        entry = entry[1..];
    }

    return std.mem.eql(u8, name, entry);
}

pub fn get(self: *AssetsManager, name: []const u8) !Asset {
    var file_name_buffer: [std.fs.max_name_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

    var reader = std.Io.Reader.fixed(self.tar_data);

    var tar_iter = tar.Iterator.init(&reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });

    while (try tar_iter.next()) |file| {
        if (file.kind != .file) continue;
        if (!matchesName(name, file.name)) continue;

        const reader_start = reader.seek;
        const reader_end = reader_start + file.size;

        return .{
            .reader = .fixed(self.tar_data[reader_start..reader_end]),
            .size = file.size,
        };
    }

    return error.NotFound;
}

pub fn getAlloc(self: *AssetsManager, allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var file_name_buffer: [std.fs.max_name_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

    var reader = std.Io.Reader.fixed(self.tar_data);

    var tar_iter = tar.Iterator.init(&reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });

    while (try tar_iter.next()) |file| {
        if (file.kind != .file) continue;
        if (!matchesName(name, file.name)) continue;

        const buffer = try allocator.alloc(u8, file.size);
        var writer = std.Io.Writer.fixed(buffer);

        try tar_iter.streamRemaining(file, &writer);

        return buffer;
    }

    return error.NotFound;
}

const std = @import("std");
const tar = std.tar;
const zstd = std.compress.zstd;
const Sha256 = std.crypto.hash.sha2.Sha256;
