const std = @import("std");
const builtin = @import("builtin");

pub const Backend = switch (builtin.os.tag) {
    .windows => @import("backend/iocp.zig"),
    .linux => @import("backend/io_uring.zig"),
    else => @compileError("Target os is not supported"),
};

pub const EventLoop = @import("EventLoop.zig");

pub const Operation = enum { read, write, none };

pub const Request = struct {
    const ControlBlock = Backend.ControlBlock;

    handle: if (builtin.os.tag == .windows) *anyopaque else i32,
    op_data: union(Operation) {
        read: []u8,
        write: []const u8,
        none: void,
    },
    control_block: ControlBlock = std.mem.zeroes(ControlBlock),
};

pub const Result = struct {
    req: *Request,
    od_res: union(Operation) {
        read: usize,
        write: usize,
        none,
    },
};

test Backend {
    std.testing.refAllDeclsRecursive(Backend);
}

test EventLoop {
    std.testing.refAllDeclsRecursive(EventLoop);
}

