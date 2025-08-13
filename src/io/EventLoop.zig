//! Event loop to handle async io
const EventLoop = @This();

handle: switch (builtin.os.tag) {
    .windows => HANDLE,
    .linux => linux.fd_t,
    else => void,
},

events: std.ArrayListUnmanaged(Event) = .empty,

pub fn init() !EventLoop {
    return switch (builtin.os.tag) {
        .windows => initWindows(),
        .linux => initLinux(),
        else => initPosix(),
    };
}

pub fn run(self: *const EventLoop) !void {
    return switch (builtin.os.tag) {
        .windows => {},
        .linux => self.runLinux(),
        else => {},
    };
}

fn initLinux() !EventLoop {
    const handle: linux.fd_t = @intCast(linux.epoll_create1(0));
    return .{
        .handle = handle,
    };
}

fn initWindows() !EventLoop {
    const handle =
        win32.system.io.CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0);

    return .{
        .handle = handle,
    };
}

// Posix systems other than linux will not have a handle
// to epoll or iocp, It will mostly just relay on libc poll
fn initPosix() !EventLoop {
    return .{};
}

pub fn addEvent(self: *EventLoop, allocator: Allocator, event: Event) !void {
    try self.events.append(allocator, event);

    switch (builtin.os.tag) {
        .windows => {},
        .linux => {
            event.control_block.data.ptr = self.events.items.len - 1;
            linux.epoll_ctl(self.handle, linux.EPOLL.CTL_ADD, event.handle, event.control_block);
        },
        else => {},
    }
}

fn runLinux(self: *EventLoop) !void {
    var events: [10]linux.epoll_event = undefined;

    while (true) {
        const count = linux.epoll_wait(self.handle, &events, 10, -1);

        for (0..count) |i| {
            const event_index = events[i].data.ptr;
            const event_ptr = &self.events.items[event_index];
            event_ptr.callback_fn(event_ptr, event_ptr.data);
        }
    }
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
