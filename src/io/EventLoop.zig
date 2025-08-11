//! Event loop to handle async io
const EventLoop = @This();

const MAX_EVENTS = 10;

handle: switch (builtin.os.tag) {
    .windows => HANDLE,
    .linux => linux.fd_t,
    else => void,
},

events: [MAX_EVENTS]Event = undefined,
events_count: usize = 0,

pub fn init() !EventLoop {
    return switch (builtin.os.tag) {
        .windows => initWindows(),
        .linux => initLinux(),
        else => initPosix(),
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

fn handleDoneEvent(self: *EventLoop, idx: usize) !void {
    const event = &self.events[idx];
    event.callback(event.data, &self.events[idx]);
}

pub fn addEvent(self: *EventLoop, event: Event) !void {
    self.events[self.events_count] = event;
    self.events_count += 1;
}

const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;
const win32 = @import("win32");

const Event = @import("Event.zig");

const HANDLE = win32.foundation.HANDLE;
const INVALID_HANDLE_VALUE = win32.foundation.INVALID_HANDLE_VALUE;
