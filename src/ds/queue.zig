const std = @import("std");

pub fn BoundedQueue(T: type, default_value: T, max_slots: comptime_int) type {
    return struct {
        comptime {
            if (!std.math.isPowerOfTwo(max_slots))
                @compileError("Queue max_slots should be power of two");
        }

        const Self = @This();

        pub const empty = Self{};

        pub const limit = max_slots;

        const max_mask = max_slots - 1;

        queue: [max_slots]T = [1]T{default_value} ** max_slots,
        read: usize = 0,
        write: usize = 0,
        count: usize = 0,

        pub fn pop(self: *Self) ?T {
            if (self.count == 0) return null;
            const value = self.queue[self.read];

            self.read += 1;
            self.read &= max_mask;

            self.count -= 1;
            return value;
        }

        pub const PushError = error{
            QueueIsFull,
        };

        pub fn push(self: *Self, event: T) PushError!void {
            if (self.count == max_slots) return error.QueueIsFull;
            self.queue[self.write] = event;

            self.write += 1;
            self.write &= max_mask;

            self.count += 1;
        }
    };
}

test BoundedQueue {
    const Queue = BoundedQueue(u32, 0, 4);

    var q = Queue.empty;

    // Starts empty.
    try std.testing.expect(q.pop() == null);

    // Fill the queue.
    try q.push(1);
    try q.push(2);
    try q.push(3);
    try q.push(4);

    // Cannot overfill.
    try std.testing.expectError(error.QueueIsFull, q.push(5));

    // Pop a couple to force wrap-around.
    try std.testing.expectEqual(1, q.pop());
    try std.testing.expectEqual(2, q.pop());

    // Wrap around.
    try q.push(5);
    try q.push(6);

    // FIFO order is preserved.
    try std.testing.expectEqual(3, q.pop());
    try std.testing.expectEqual(4, q.pop());
    try std.testing.expectEqual(5, q.pop());
    try std.testing.expectEqual(6, q.pop());

    // Empty again.
    try std.testing.expect(q.pop() == null);
    try std.testing.expectEqual(0, q.count);

    // Reusable.
    try q.push(42);
    try std.testing.expectEqual(42, q.pop());
    try std.testing.expect(q.pop() == null);
}
