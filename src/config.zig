const std = @import("std");
const color = @import("zerotty").terminal.color;

const Theme = enum {
    dark,
    light,
};

pub const Config = struct {
    theme: ?Theme = .dark,

    fg_color: color.RGBA = .white,
    bg_color: color.RGBA = color.RGBA.mix(.white, .black, 0.94).alpha(240),
    /// Font size in pixels (vertical height of a glyph).
    font_size: u32 = 32,
    gpu_acceleration: bool = true,
};

pub const ConfigJson = struct {
    theme: []const u8 = "",
    fg_color: []const u8 = "",
    bg_color: []const u8 = "",
    font_size: u32 = 20,

    fn resolveColorValue(color_str: []const u8) !color.RGBA {
        if (color_str.len > 0 and color_str[0] == '#') {
            return switch (color_str.len) {
                7 => color.RGBA.fromRGBHexString(color_str),
                9 => color.RGBA.fromRGBAHexString(color_str),
                else => error.InvalidColorValue,
            };
        } else if (std.meta.stringToEnum(color.CSSColors, color_str)) |css| {
            return css.toRGBA();
        } else return error.InvalidColorValue;
    }

    pub fn resolve(cfg: ConfigJson) !Config {
        const fg_color = resolveColorValue(cfg.fg_color) catch return error.InvalidFgColorValue;
        const bg_color = resolveColorValue(cfg.bg_color) catch return error.InvalidBgColorValue;

        return .{
            .fg_color = fg_color,
            .bg_color = bg_color,
            .font_size = cfg.font_size,
        };
    }
};

fn configFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    env_map: *std.process.Environ.Map,
) !std.Io.File {
    const home = env_map.get("HOME") orelse return error.FileNotFound;
    const config_dir_path = try std.fs.path.join(allocator, &.{ home, ".config" });
    defer allocator.free(config_dir_path);

    std.log.debug("config path {s}/zerotty.json", .{config_dir_path});

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
        ConfigJson,
        allocator,
        data,
        .{ .allocate = .alloc_if_needed },
    );

    defer config.deinit();

    return config.value.resolve();
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
