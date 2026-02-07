pub fn Vec2(T: type) type {
    return packed struct {
        x: T,
        y: T,
        pub const zero = std.mem.zeroes(@This());

        pub fn add(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return .{
                .x = a.x + b.x,
                .y = a.y + b.y,
            };
        }

        pub fn sub(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return .{
                .x = a.x - b.x,
                .y = a.y - b.y,
            };
        }

        pub fn subScaler(vec: Vec2(T), scaler: T) Vec2(T) {
            return .{
                .x = vec.x - scaler,
                .y = vec.y - scaler,
            };
        }

        pub fn div(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return .{
                .x = a.x / b.x,
                .y = a.y / b.y,
            };
        }

        pub fn mul(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return .{
                .x = a.x * b.x,
                .y = a.y * b.y,
            };
        }

        pub fn scale(a: Vec2(T), scaler: T) Vec2(T) {
            return .{
                .x = a.x * scaler,
                .y = a.y * scaler,
            };
        }

        pub fn inv(vec: Vec2(T)) Vec2(T) {
            std.debug.assert(vec.x != 0 and vec.y != 0);
            return .{
                .x = 1 / vec.x,
                .y = 1 / vec.y,
            };
        }

        pub fn simdVector(vec: Vec2(T)) @Vector(2, T) {
            return @bitCast(vec);
        }
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
