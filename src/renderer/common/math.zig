pub fn Vec2(T: type) type {
    return extern struct {
        x: T,
        y: T,
        pub const zero = std.mem.zeroes(@This());
    };
}

pub fn Vec3(T: type) type {
    return packed struct {
        x: T,
        y: T,
        z: T,
        pub const zero = std.mem.zeroes(@This());
    };
}

pub fn Vec4(T: type) type {
    return packed struct {
        x: T,
        y: T,
        z: T,
        w: T,
        pub const zero = std.mem.zeroes(@This());
    };
}

pub fn makeOrtho2D(width: f32, height: f32) [4]Vec4(f32) {
    return .{
        .{ .x = 2 / width, .y = 0, .z = 0, .w = 0 },
        .{ .x = 0, .y = 2 / height, .z = 0, .w = 0 },
        .{ .x = 0, .y = 0, .z = -1, .w = 0 },
        .{ .x = -1, .y = -1, .z = 0, .w = 1 },
    };
}

const std = @import("std");
