const std = @import("std");

fn OptimizedRingArray(T: type) type {
    return struct {
        const Self = @This();

        view: []T,
        capacity: usize,

        read: usize = 0,
        write: usize = 0,
        count: usize = 0,

        pub const InitError = error{
            AlignmentNotMatch,
            BufferSizeNotOptimal,
            Unexpected,
        };

        fn initFromDupleMappedBuffer(full_view: []u8) InitError!Self {
            if (!std.mem.isAligned(
                @intFromPtr(full_view.ptr),
                @alignOf(T),
            )) {
                return error.AlignmentNotMatch;
            }

            const view = std.mem.bytesAsSlice(T, full_view);
            const capacity = std.math
                .divExact(usize, full_view.len, @sizeOf(T) * 2) catch |err| {
                return switch (err) {
                    error.UnexpectedRemainder => error.BufferSizeNotOptimal,
                    else => error.Unexpected,
                };
            };

            return .{
                .view = view,
                .capacity = capacity,
            };
        }
    };
}

pub fn RingArray(T: type) type {}
