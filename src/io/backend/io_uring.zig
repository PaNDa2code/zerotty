const std = @import("std");
const linux = std.os.linux;

pub const Context = struct {
    const Self = @This();

    const SubmissionQueue = struct {
        head: *u32,
        tail: *u32,
        mask: *u32,
        entries: *u32,
        flags: *u32,
        dropped: *u32,
        array: [*]u32,
        mmap_ptr: [*]align(std.heap.pageSize()) u8,
        mmap_size: usize,
    };

    const CompletionQueue = struct {
        head: *u32,
        tail: *u32,
        mask: *u32,
        entries: *u32,
        overflow: *u32,
        cqes: [*]linux.io_uring_cqe,
        mmap_ptr: [*]align(std.heap.pageSize()) u8,
        mmap_size: usize,
    };

    fd: linux.fd_t,

    sq: SubmissionQueue,
    cq: CompletionQueue,
    sqes: []linux.io_uring_sqe,

    pub fn setup(self: *Self) !void {
        var params = std.mem.zeroes(linux.io_uring_params);

        const fd: linux.fd_t = @truncate(@as(isize, @bitCast(linux.io_uring_setup(8, &params))));
        if (fd < 0) return error.IoUringSetupFailed;

        errdefer _ = linux.close(fd);

        const sq_size = params.sq_off.array + params.sq_entries * @sizeOf(u32);
        const cq_size = params.cq_off.cqes + params.cq_entries * @sizeOf(linux.io_uring_cqe);
        const sqes_size = params.sq_entries * @sizeOf(linux.io_uring_sqe);

        const sq_address = linux.mmap(
            null,
            sq_size,
            linux.PROT.READ | linux.PROT.WRITE,
            .{ .TYPE = .SHARED, .POPULATE = true },
            fd,
            linux.IORING_OFF_SQ_RING,
        );

        if (sq_address == 0) return error.SqMmapFailed;

        errdefer _ = linux.munmap(@ptrFromInt(sq_address), sq_size);

        const cq_address = if (params.features & linux.IORING_FEAT_SINGLE_MMAP != 0)
            sq_address
        else
            linux.mmap(
                null,
                cq_size,
                linux.PROT.READ | linux.PROT.WRITE,
                .{ .TYPE = .SHARED, .POPULATE = true },
                fd,
                linux.IORING_OFF_CQ_RING,
            );

        if (cq_address == 0) return error.CqMmapFailed;

        errdefer _ = linux.munmap(@ptrFromInt(cq_address), cq_size);

        const sqes_address = linux.mmap(
            null,
            sqes_size,
            linux.PROT.READ | linux.PROT.WRITE,
            .{ .TYPE = .SHARED, .POPULATE = true },
            fd,
            linux.IORING_OFF_SQES,
        );

        if (sqes_address == 0 or
            std.math.signbit(@as(isize, @bitCast(sqes_address))))
        {
            std.log.err("sqes_address = 0x{x}", .{sqes_address});
            return error.SqesMmapFailed;
        }

        self.fd = fd;

        self.sq = .{
            .head = @ptrFromInt(sq_address + params.sq_off.head),
            .tail = @ptrFromInt(sq_address + params.sq_off.tail),
            .mask = @ptrFromInt(sq_address + params.sq_off.ring_mask),
            .entries = @ptrFromInt(sq_address + params.sq_off.ring_entries),
            .flags = @ptrFromInt(sq_address + params.sq_off.flags),
            .dropped = @ptrFromInt(sq_address + params.sq_off.dropped),
            .array = @ptrFromInt(sq_address + params.sq_off.array),
            .mmap_ptr = @ptrFromInt(sq_address),
            .mmap_size = sq_size,
        };

        self.cq = .{
            .head = @ptrFromInt(cq_address + params.cq_off.head),
            .tail = @ptrFromInt(cq_address + params.cq_off.tail),
            .mask = @ptrFromInt(cq_address + params.cq_off.ring_mask),
            .entries = @ptrFromInt(cq_address + params.cq_off.ring_entries),
            .overflow = @ptrFromInt(cq_address + params.cq_off.overflow),
            .cqes = @ptrFromInt(cq_address + params.cq_off.cqes),
            .mmap_ptr = @ptrFromInt(cq_address),
            .mmap_size = cq_size,
        };

        self.sqes = @as([*]linux.io_uring_sqe, @ptrFromInt(sqes_address))[0..params.sq_entries];
    }

    pub fn close(self: *const Self) void {
        _ = linux.munmap(@ptrCast(@alignCast(self.sqes.ptr)), self.sqes.len * @sizeOf(linux.io_uring_sqe));
        _ = linux.munmap(self.sq.mmap_ptr, self.sq.mmap_size);

        if (self.sq.mmap_ptr != self.cq.mmap_ptr)
            _ = linux.munmap(self.cq.mmap_ptr, self.cq.mmap_size);

        _ = linux.close(self.fd);
    }
    pub fn register(self: *const Self, req: *const Request) !void {
        _ = self;
        _ = req;
    }

    /// The `Request` must outlive its dequeuing.
    pub fn queue(self: *const Self, req: *const Request) !void {
        const tail = @atomicLoad(u32, self.sq.tail, .acquire);
        const head = @atomicLoad(u32, self.sq.head, .acquire);
        const mask = self.sq.mask.*;

        if (tail - head >= self.sq.entries.*) {
            return error.QueueFull;
        }

        const index = tail & mask;
        var sqe = &self.sqes[index];

        sqe.* = std.mem.zeroes(linux.io_uring_sqe);
        sqe.fd = @intCast(req.handle);
        sqe.user_data = @intFromPtr(req);

        switch (req.op_data) {
            .read => |buf| {
                sqe.opcode = .READ;
                sqe.addr = @intFromPtr(buf.ptr);
                sqe.len = @intCast(buf.len);
                sqe.off = 0;
            },
            .write => |buf| {
                sqe.opcode = .WRITE;
                sqe.addr = @intFromPtr(buf.ptr);
                sqe.len = @intCast(buf.len);
                sqe.off = 0;
            },
            .none => {
                sqe.opcode = .NOP;
            },
        }

        self.sq.array[index] = index;

        @atomicStore(u32, self.sq.tail, tail + 1, .release);
    }

    pub fn submit(self: *const Self) !void {
        const res = linux.io_uring_enter(
            self.fd,
            @atomicLoad(u32, self.sq.tail, .acquire) - @atomicLoad(u32, self.sq.head, .acquire),
            0,
            0,
            null,
        );

        if (linux.E.init(res) != .SUCCESS) {
            return error.SubmitFailed;
        }
    }

    pub fn dequeue(self: *const Self, res: *i32) !*const Request {
        const ret = linux.io_uring_enter(self.fd, 0, 1, linux.IORING_ENTER_GETEVENTS, null);
        if (linux.E.init(ret) != .SUCCESS) {
            return error.DequeueFailed;
        }

        const head = @atomicLoad(u32, self.cq.head, .acquire);
        const tail = @atomicLoad(u32, self.cq.tail, .acquire);

        if (head == tail) {
            return error.NoCompletion;
        }

        const mask = self.cq.mask.*;
        const cqe = &self.cq.cqes[head & mask];

        res.* = cqe.res;
        const req: *const Request = @ptrFromInt(cqe.user_data);

        @atomicStore(u32, self.cq.head, head + 1, .release);

        return req;
    }

    pub fn dequeue_timeout(self: *const Self, timeout_ms: u32, res: *i32) !?*const Request {
        const head = @atomicLoad(u32, self.cq.head, .acquire);
        const tail = @atomicLoad(u32, self.cq.tail, .acquire);

        if (head != tail) {
            const mask = self.cq.mask.*;
            const cqe = &self.cq.cqes[head & mask];

            res.* = cqe.res;
            const req: *const Request = @ptrFromInt(cqe.user_data);

            @atomicStore(u32, self.cq.head, head + 1, .release);

            return req;
        }

        if (timeout_ms == 0) {
            return null;
        }

        var ts = linux.kernel_timespec{
            .sec = 0,
            .nsec = @as(i64, timeout_ms) * std.time.ns_per_ms,
        };

        const ret = linux.io_uring_enter(
            self.fd,
            0,
            1,
            linux.IORING_ENTER_GETEVENTS,
            @ptrCast(&ts),
        );

        if (ret < 0) {
            const err = linux.E.init(ret);
            return if (err == .TIME) null else error.DequeueFailed;
        }

        const new_head = @atomicLoad(u32, self.cq.head, .acquire);
        const new_tail = @atomicLoad(u32, self.cq.tail, .acquire);

        if (new_head == new_tail) {
            return null;
        }

        const mask = self.cq.mask.*;
        const cqe = &self.cq.cqes[new_head & mask];

        res.* = cqe.res;
        const req: *const Request = @ptrFromInt(cqe.user_data);

        @atomicStore(u32, self.cq.head, new_head + 1, .release);

        return req;
    }
};

pub const ControlBlock = void;

const root = @import("../root.zig");
const Request = root.Request;
const Operation = root.Operation;
const Result = root.Result;

test "io_uring pipe write test" {
    const c_unistd = @cImport({
        @cInclude("unistd.h");
    });

    var context: Context = undefined;
    try context.setup();
    defer context.close();

    // Create a pipe
    var fds: [2]c_int = undefined;
    if (c_unistd.pipe(&fds) != 0) {
        std.debug.print("pipe creation failed\n", .{});
        return;
    }
    defer _ = c_unistd.close(fds[0]);
    defer _ = c_unistd.close(fds[1]);

    // Buffer to write
    const buf: []const u8 = @as([1000]u8, @splat(0xAA))[0..];

    // Queue a write to the pipe's write end
    var req = Request{
        .handle = @intCast(fds[1]),
        .op_data = .{ .write = buf },
    };

    try context.queue(&req);
    try context.submit();

    var res: i32 = 0;
    const completed_req = try context.dequeue(&res);
    try std.testing.expect(completed_req == &req);
    try std.testing.expect(res == buf.len);

    var read_buf: [1002]u8 = undefined;
    const n = c_unistd.read(fds[0], &read_buf, @intCast(read_buf.len));
    try std.testing.expectEqualSlices(u8, buf[0..], read_buf[0..@intCast(n)]);
}
