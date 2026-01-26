pub fn CircularArray(T: type) type {
    return struct {
        const Self = @This();

        buffer: CircularBuffer,
        slice_view: []T, // owned to the CircularBuffer

        capacity: usize,

        head: usize = 0,
        len: usize = 0,

        pub fn init(minimum_capacity: usize) !Self {
            if (@alignOf(T) > CircularBuffer.page_size)
                @compileError("Type alignment is bigger that the page size");
            const minimum_byte_size = minimum_capacity * @sizeOf(T);
            const buffer = try CircularBuffer.new(minimum_byte_size);
            return initFromBuffer(buffer);
        }

        pub fn initFromBuffer(buffer: CircularBuffer) !Self {
            const capacity = try std.math.divExact(usize, buffer.view_size, @sizeOf(T));
            const slice_view = @as([*]T, @ptrCast(buffer.buffer.ptr))[0 .. capacity * 2];
            return .{ .buffer = buffer, .slice_view = slice_view, .capacity = capacity };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        pub fn push(self: *Self, element: T) !void {
            self.slice_view[self.head + self.len] = element;

            if (self.len < self.capacity) {
                self.len += 1;
            } else {
                self.head += 1;
                if (self.head >= self.capacity) {
                    self.head = 0;
                }
            }
        }

        pub fn get(self: *const Self, index: usize) T {
            return self.slice_view[self.head + index];
        }

        fn mut_slice(self: *Self) []T {
            return self.slice_view[self.head..][0..self.capacity];
        }

        pub fn slice(self: *const Self) []const T {
            return self.slice_view[self.head..][0..self.len];
        }
    };
}

const std = @import("std");
const CircularBuffer = @import("CircularBuffer.zig");

test CircularArray {
    var array = try CircularArray(u64).init(100);
    defer array.deinit();

    for (0..array.capacity * 3) |i| {
        const n = i % array.capacity;
        try array.push(n);
    }

    for (0.., array.slice()) |i, n| {
        try std.testing.expectEqual(i, n);
    }
}
