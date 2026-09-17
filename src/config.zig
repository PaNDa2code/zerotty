const std = @import("std");

const Theme = enum {
    dark,
    light,
};

pub const Config = struct {
    theme: ?Theme = .dark,
    /// Font size in pixels (vertical height of a glyph).
    font_size: u32 = 32,
    gpu_acceleration: bool = true,
};

pub fn configFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    env_map: *std.process.Environ.Map,
) !std.Io.File {
    const home = env_map.get("HOME") orelse return error.FileNotFound;
    const config_dir_path = try std.fs.path.join(allocator, &.{ home, ".config" });
    defer allocator.free(config_dir_path);

    const config_dir = try std.Io.Dir.openDirAbsolute(io, config_dir_path, .{});
    defer config_dir.close(io);

    return config_dir.openFile(io, "zerotty.json", .{});
}

pub fn getConfig(
    io: std.Io,
    env_map: *std.process.Environ.Map,
    allocator: std.mem.Allocator,
) !Config {
    const config_file = try configFile(io, allocator, env_map);
    defer config_file.close(io);

    const size = try config_file.length(io);
    const data = try allocator.alloc(u8, @intCast(size));
    defer allocator.free(data);

    _ = try config_file.readPositionalAll(io, data, 0);

    const config = try std.json.parseFromSlice(
        Config,
        allocator,
        data,
        .{ .allocate = .alloc_if_needed },
    );

    defer config.deinit();

    return config.value;
}

test Config {
    var parsed = try std.json.parseFromSlice(
        Config,
        std.testing.allocator,
        "{}",
        .{ .allocate = .alloc_if_needed },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 32), parsed.value.font_size);
}
