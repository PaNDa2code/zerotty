const AssetsManager = @This();

pub var instance: AssetsManager = undefined;

pub const assets_archive = @embedFile("assets.tar.zst");

archive_data: []const u8,
allocator: std.mem.Allocator,
reader: std.Io.Reader = .failing,
tar_iter: tar.Iterator = undefined,

pub fn init(allocator: std.mem.Allocator, compressed_data: []const u8) !AssetsManager {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();

    var reader: std.Io.Reader = .fixed(compressed_data);
    var zstd_decompress: zstd.Decompress = .init(&reader, &.{}, .{});
    _ = try zstd_decompress.reader.streamRemaining(&writer.writer);
    return .{
        .archive_data = try writer.toOwnedSlice(),
        .allocator = allocator,
    };
}

pub fn deinit(self: *AssetsManager) void {
    self.allocator.free(self.archive_data);
}

var file_name_buffer: [std.fs.max_name_bytes]u8 = undefined;
var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

fn tarReset(self: *AssetsManager) void {
    self.reader = std.Io.Reader.fixed(self.archive_data);
    self.tar_iter = tar.Iterator.init(&self.reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });
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

pub fn get(self: *AssetsManager, name: []const u8, writer: *std.Io.Writer) !void {
    self.tarReset();

    while (try self.tar_iter.next()) |file| {
        if (file.kind != .file) continue;
        if (!matchesName(name, file.name)) continue;

        _ = try self.tar_iter.streamRemaining(file, writer);
        return;
    }

    return error.NotFound;
}

pub fn getAlloc(self: *AssetsManager, allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    self.tarReset();

    while (try self.tar_iter.next()) |file| {
        if (file.kind != .file) continue;
        if (!matchesName(name, file.name)) continue;

        const buffer = try allocator.alloc(u8, file.size);
        var writer = std.Io.Writer.fixed(buffer);

        _ = try self.tar_iter.streamRemaining(file, &writer);

        return buffer;
    }

    return error.NotFound;
}

const std = @import("std");
const tar = std.tar;
const zstd = std.compress.zstd;
