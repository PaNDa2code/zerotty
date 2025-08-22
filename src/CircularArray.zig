pub fn CircularArray(T: type) type {
    return struct {
        const Self = @This();

        buffer: CircularBuffer,
        len: usize = 0,

        pub fn init(size: usize) !Self {
            if (@alignOf(T) > CircularBuffer.page_size)
                @compileError("Type alignment is bigger that the page size");
            const byte_size = try std.math.divCeil(usize, size, @sizeOf(T));
            const buffer = try CircularBuffer.new(byte_size);
            const len = try std.math.divCeil(usize, buffer.view_size, @sizeOf(T));
            return .{ .buffer = buffer, .len = len };
        }

        pub fn initFromBuffer(buffer: CircularBuffer) Self {
            const len = try std.math.divCeil(usize, buffer.view_size, @sizeOf(T));
            return .{ .buffer = buffer, .len = len };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        pub fn push(self: *Self, elemnt: T) !void {
            const bytes = std.mem.asBytes(&elemnt);
            const written_bytes = try self.buffer.write(bytes);
            std.debug.assert(written_bytes == @sizeOf(T));
        }

        pub fn get(self: *const Self, index: usize) T {
            return @constCast(self).slice()[index];
        }

        fn mut_slice(self: *Self) []T {
            return @alignCast(std.mem.bytesAsSlice(T, self.buffer.buffer[self.buffer.start..self.buffer.view_size]));
        }

        pub fn slice(self: *const Self) []const T {
            return @constCast(self).mut_slice();
        }
    };
}

const std = @import("std");
const CircularBuffer = @import("CircularBuffer.zig");

test CircularArray {
    var array = try CircularArray(u128).init(100);
    defer array.deinit();

    try array.push(100);

    try std.testing.expectEqual(100, array.get(0));
}
