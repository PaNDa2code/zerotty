const File = @This();

const Handle = switch (builtin.os.tag) {
    .windows => HANDLE,
    else => linux.fd_t,
};

handle: Handle,

pub fn init(handle: Handle) !File {
    if (builtin.os.tag != .windows)
        try setNonBlockingPosix(handle);

    return .{ .handle = handle };
}

fn setNonBlockingPosix(handle: Handle) !void {
    const flags = try posix.fcntl(handle, linux.F.GETFL, 0);
    _ = try posix.fcntl(handle, linux.F.SETFL, flags | @as(u32, @bitCast(linux.O{ .NONBLOCK = true })));
}

pub fn asyncRead(self: File, allocator: Allocator, buf: []u8, callback: Event.CallBack, data: ?*anyopaque) !Event {
    const control_block = try allocator.create(Event.ControlBlock);

    return switch (builtin.os.tag) {
        .windows => {},
        .linux => self.asyncReadLinux(buf, callback, control_block, data),
        else => {},
    };
}

fn asyncReadLinux(self: File, buf: []u8, callback: Event.CallBack, _: *Event.ControlBlock, data: ?*anyopaque) !Event {
    _ = posix.read(self.handle, buf) catch |err| {
        switch (err) {
            error.WouldBlock => {},
            else => return err,
        }
    };

    return .{
        .data = data,
        .handle = self.handle,
        .callback_fn = callback,
    };
}

const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;
const win32 = @import("win32");

const Allocator = std.mem.Allocator;

const Event = @import("Event.zig");

const HANDLE = win32.foundation.HANDLE;
const INVALID_HANDLE_VALUE = win32.foundation.INVALID_HANDLE_VALUE;

const OVERLAPPED = win32.system.io.OVERLAPPED;
const OVERLAPPED_ENTRY = win32.system.io.OVERLAPPED_ENTRY;

const c_aio = @cImport({
    @cInclude("aio.h");
});
