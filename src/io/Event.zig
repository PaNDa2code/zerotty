const Event = @This();

const Handle = switch (builtin.os.tag) {
    .windows => HANDLE,
    else => linux.fd_t,
};

pub const CallBack = *const fn (event: *const Event, buf: []u8, data: ?*anyopaque) void;

pub const ControlBlock = switch (builtin.os.tag) {
    .windows => OVERLAPPED,
    // linux epoll doesn't require to have epoll_event struct alive
    .linux => void,
    else => c_aio.aiocb,
};

handle: Handle,

data: ?*anyopaque,

callback_fn: CallBack,
dispatch_fn: *const fn (handle: Handle, buf: []u8) usize,
dispatch_buf: []u8,

control_block: ?*ControlBlock = null,

pub fn deinit(self: *Event, allocator: Allocator) void {
    if (self.control_block) |cb|
        allocator.destroy(cb);
}

const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;
const win32 = @import("win32");

const Allocator = std.mem.Allocator;

const HANDLE = win32.foundation.HANDLE;
const INVALID_HANDLE_VALUE = win32.foundation.INVALID_HANDLE_VALUE;

const OVERLAPPED = win32.system.io.OVERLAPPED;
const OVERLAPPED_ENTRY = win32.system.io.OVERLAPPED_ENTRY;

const c_aio = @cImport({
    @cInclude("aio.h");
});
