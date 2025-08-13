const Event = @This();

const Handle = switch (builtin.os.tag) {
    .windows => HANDLE,
    else => linux.fd_t,
};

pub const CallBack = *const fn (event: *const Event, data: ?*anyopaque) void;

pub const ControlBlock = switch (builtin.os.tag) {
    .windows => OVERLAPPED,
    // linux epoll doesn't requre to have epoll_event struct alive
    .linux => void,
    else => c_aio.aiocb,
};

handle: Handle,

data: ?*anyopaque,

callback_fn: CallBack,
supmit_fn: *const fn (event: *const Event, ptr: [*]u8, len: usize) void,
control_block: ?*ControlBlock,

error_: anyerror,

pub fn deinit(self: *Event, allocator: Allocator) void {
    allocator.destroy(self.control_block);
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
