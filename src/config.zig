const std = @import("std");

const Theme = enum {
    dark,
    light,
};

const Config = struct {
    theme: ?Theme = .dark,
    font_size: u32 = 24,
    gpu_acceleration: bool = true,
};

pub fn configFilePath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return try std.fs.path.join(allocator, &.{ home, ".config/zerotty.json" });
}

pub fn configFile(allocator: std.mem.Allocator) !?std.fs.File {
    const config_path = try configFilePath(allocator);
    defer allocator.free(config_path);

    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        }
    };

    return file;
}

pub fn getConfig(allocator: std.mem.Allocator) !Config {
    const config_file = try configFile(allocator);

    if (config_file) |f| {
        const data = try f.readToEndAlloc(allocator, 10 * 1024);
        defer allocator.free(data);

        const config = try std.json.parseFromSlice(
            Config,
            allocator,
            data,
            .{ .allocate = .alloc_if_needed },
        );

        defer config.deinit();

        return config.value;
    }

    return .{};
}

test Config {
    const config = try getConfig(std.testing.allocator);
    std.log.err("{any}", .{config});
}
