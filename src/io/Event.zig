const Event = @This();

const Handle = switch (builtin.os.tag) {
    .windows => HANDLE,
    else => linux.fd_t,
};

const CallBack = *const fn (data: ?*anyopaque, event: *const Event) void;

const ControlBlock = switch (builtin.os.tag) {
    .windows => OVERLAPPED,
    .linux => void,
    .macos => c_aio.aiocb,
    else => void,
};

data: ?*anyopaque,
handle: Handle,
callback: CallBack,
control_block: ControlBlock,

pub fn init(handle: Handle, callback: CallBack, data: ?*anyopaque) Event {
    return .{
        .data = data,
        .handle = handle,
        .callback = callback,
        .control_block = std.mem.zeroes(ControlBlock),
    };
}

const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;
const win32 = @import("win32");

const HANDLE = win32.foundation.HANDLE;
const INVALID_HANDLE_VALUE = win32.foundation.INVALID_HANDLE_VALUE;

const OVERLAPPED = win32.system.io.OVERLAPPED;
const OVERLAPPED_ENTRY = win32.system.io.OVERLAPPED_ENTRY;

const c_aio = @cImport({
    @cInclude("aio.h");
});
