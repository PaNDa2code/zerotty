const std = @import("std");

pub const maxmum_input_size = 1024 * 1024 * 100;
pub const maxmum_output_size = 1024 * 1024 * 50;

pub const comperssion = std.compress.zlib;

pub fn compress(comptime input: [:0]const u8) []const u8 {
    @setEvalBranchQuota(1000_000);
    var buf = std.mem.zeroes([maxmum_output_size]u8);
    var fbs = std.io.fixedBufferStream(buf[0..]);

    var cmp = comperssion.compressor(fbs.writer(), .{}) catch unreachable;
    _ = cmp.write(input) catch unreachable;

    cmp.finish() catch unreachable;

    return fbs.context.getWritten();
}

pub fn decompress(input: []const u8) ![]const u8 {
    var buf = std.mem.zeroes([maxmum_input_size]u8);

    var fbs = std.io.fixedBufferStream(input);

    var dcp = comperssion.decompressor(fbs.reader(), .{});

    const len = try dcp.reader().readAll(buf[0..]);

    return buf[0..len];
}
