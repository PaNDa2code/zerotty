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
        .windows => self.asyncReadWindows(buf, callback, control_block, data),
        .linux => self.asyncReadLinux(buf, callback, control_block, data),
        else => {},
    };
}

fn asyncReadLinux(self: File, buf: []u8, callback: Event.CallBack, _: *Event.ControlBlock, data: ?*anyopaque) !Event {
    return .{
        .data = data,
        .handle = self.handle,
        .callback_fn = callback,
        .dispatch_fn = &readDispatshLinux,
        .dispatch_buf = buf,
    };
}

fn readDispatshLinux(handle: Handle, buf: []u8) usize {
    return posix.read(handle, buf) catch |err|
        std.debug.panic("read dispatsh failed: {}", .{err});
}

fn asyncReadWindows(
    self: File,
    buf: []u8,
    callback: Event.CallBack,
    control_block: *Event.ControlBlock,
    data: ?*anyopaque,
) !Event {
    control_block.* = std.mem.zeroes(Event.ControlBlock);

    _ = win32.storage.file_system.ReadFile(self.handle, buf.ptr, @intCast(buf.len), null, control_block);

    return .{
        .data = data,
        .handle = self.handle,
        .callback_fn = callback,
        .control_block = control_block,
        .dispatch_fn = &readDispatshWindows,
        .dispatch_buf = buf,
    };
}

fn readDispatshWindows(handle: Handle, buf: []u8) usize {
    _ = buf; // autofix
    _ = handle; // autofix
    return 0;
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
