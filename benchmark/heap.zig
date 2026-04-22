const std = @import("std");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub const ProfilingAllocator = struct {
    // Allocation size buckets
    pub const bucket_limits = [_]usize{
        32,
        64,
        128,
        256,
        512,
        1024,
        2048,
        4096,
    };

    child: Allocator,

    current: usize = 0,
    peak: usize = 0,
    total_allocated: usize = 0,
    total_freed: usize = 0,

    alloc_count: usize = 0,
    free_count: usize = 0,

    resize_grow: usize = 0,
    resize_shrink: usize = 0,
    resize_fail: usize = 0,

    alloc_hist: [bucket_limits.len + 1]usize = .{0} ** (bucket_limits.len + 1),

    alloc_bytes_hist: [bucket_limits.len + 1]usize = .{0} ** (bucket_limits.len + 1),

    pub fn init(child: Allocator) ProfilingAllocator {
        return .{ .child = child };
    }

    pub fn allocator(self: *ProfilingAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn bucketIndex(len: usize) usize {
        inline for (bucket_limits, 0..) |limit, i| {
            if (len <= limit) return i;
        }
        return bucket_limits.len;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));

        const ptr = self.child.vtable.alloc(self.child.ptr, len, alignment, ra) orelse return null;

        self.current += len;
        self.total_allocated += len;
        self.alloc_count += 1;
        self.peak = @max(self.peak, self.current);

        const idx = bucketIndex(len);
        self.alloc_hist[idx] += 1;
        self.alloc_bytes_hist[idx] += len;

        return ptr;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, ra: usize) void {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));

        std.debug.assert(self.current >= buf.len);

        self.current -= buf.len;
        self.total_freed += buf.len;
        self.free_count += 1;

        self.child.vtable.free(self.child.ptr, buf, alignment, ra);
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));

        if (!self.child.vtable.resize(self.child.ptr, buf, alignment, new_len, ra)) {
            self.resize_fail += 1;
            return false;
        }

        if (new_len > buf.len) {
            const delta = new_len - buf.len;
            self.current += delta;
            self.total_allocated += delta;
            self.resize_grow += 1;
        } else if (new_len < buf.len) {
            const delta = buf.len - new_len;
            self.current -= delta;
            self.total_freed += delta;
            self.resize_shrink += 1;
        }

        self.peak = @max(self.peak, self.current);
        return true;
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *ProfilingAllocator = @ptrCast(@alignCast(ctx));

        const ptr = self.child.vtable.remap(self.child.ptr, buf, alignment, new_len, ra) orelse return null;

        if (new_len > buf.len) {
            const delta = new_len - buf.len;
            self.current += delta;
            self.total_allocated += delta;
        } else if (new_len < buf.len) {
            const delta = buf.len - new_len;
            self.current -= delta;
            self.total_freed += delta;
        }

        self.peak = @max(self.peak, self.current);
        return ptr;
    }

    pub fn dump(self: *ProfilingAllocator) void {
        std.debug.print(
            \\ProfilingAllocator:
            \\  current: {B:.02}
            \\  peak:    {B:.02}
            \\  allocs:  {d}
            \\  frees:   {d}
            \\  resize:  grow={d} shrink={d} fail={d}
            \\
        ,
            .{
                self.current,
                self.peak,
                self.alloc_count,
                self.free_count,
                self.resize_grow,
                self.resize_shrink,
                self.resize_fail,
            },
        );

        // inline for (bucket_limits, 0..) |limit, i| {
        //     std.debug.print(
        //         "  <= {d:4} B : {d} allocs, {d} bytes\n",
        //         .{
        //             limit,
        //             self.alloc_hist[i],
        //             self.alloc_bytes_hist[i],
        //         },
        //     );
        // }
        //
        // std.debug.print(
        //     "  >  {d:4} B : {d} allocs, {d} bytes\n",
        //     .{
        //         bucket_limits[bucket_limits.len - 1],
        //         self.alloc_hist[bucket_limits.len],
        //         self.alloc_bytes_hist[bucket_limits.len],
        //     },
        // );
    }
};
