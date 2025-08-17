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

pub fn deinit(self: *EventLoop, allocator: Allocator) void {
    for (self.events.items) |*ev|
        ev.deinit(allocator);

    defer self.events.deinit(allocator);

    return switch (builtin.os.tag) {
        .windows => self.deinitWindows(allocator),
        .linux => self.deinitLinux(),
        else => self.deinitPosix(),
    };
}

pub fn run(self: *const EventLoop) !void {
    return switch (builtin.os.tag) {
        .windows => self.runWindows(),
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
        win32.system.io.CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0) orelse
        return error.CreateIoCompletionPortFailed;

    return .{
        .handle = handle,
    };
}

fn deinitWindows(self: *EventLoop, allocator: Allocator) void {
    _ = allocator; // autofix
    _ = self; // autofix
}

// Posix systems other than linux will not have a handle
// to epoll or iocp, It will mostly just relay on libc poll
fn initPosix() !EventLoop {
    return .{};
}

pub fn addEvent(self: *EventLoop, allocator: Allocator, event: Event) !void {
    try self.events.append(allocator, event);

    switch (builtin.os.tag) {
        .windows => {
            _ = win32.system.io.CreateIoCompletionPort(
                event.handle,
                self.handle,
                self.events.items.len - 1,
                0,
            );
        },
        .linux => {
            var epoll_event = std.mem.zeroes(linux.epoll_event);
            epoll_event.data.ptr = self.events.items.len - 1;
            epoll_event.events = linux.EPOLL.IN;
            _ = linux.epoll_ctl(self.handle, linux.EPOLL.CTL_ADD, event.handle, &epoll_event);
        },
        else => {},
    }
}

fn runLinux(self: *const EventLoop) !void {
    var events: [10]linux.epoll_event = undefined;

    while (true) {
        const count = linux.epoll_wait(self.handle, &events, 10, -1);

        if (@as(isize, @bitCast(count)) == -1)
            std.debug.panic("epoll_wait failed: {}", .{count});

        for (0..count) |i| {
            const event_index = events[i].data.ptr;
            const event_ptr = &self.events.items[event_index];
            const avilable: i32 = 0;
            _ = linux.ioctl(event_ptr.handle, 0x541B, @intFromPtr(&avilable));
            const len = event_ptr.dispatch_fn(event_ptr.handle, event_ptr.dispatch_buf);
            event_ptr.callback_fn(event_ptr, event_ptr.dispatch_buf[0..len], event_ptr.data);
            return;
        }
    }
}

fn runWindows(self: *const EventLoop) !void {
    while (true) {
        var len: u32 = 0;
        var event_index: usize = 0;
        var control_block: *Event.ControlBlock = undefined;
        if (win32.system.io.GetQueuedCompletionStatus(
            self.handle,
            &len,
            &event_index,
            @ptrCast(&control_block),
            0,
        ) == 0) {
            return;
        } else {
            const event_ptr = &self.events.items[event_index];
            event_ptr.callback_fn(event_ptr, event_ptr.dispatch_buf[0..len], event_ptr.data);

            // TODO: i'll handle this better ^_^
            _ = win32.storage.file_system.ReadFile(event_ptr.handle, event_ptr.dispatch_buf.ptr, @intCast(event_ptr.dispatch_buf.len), null, event_ptr.control_block);
            // return;
        }
    }
}

const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;
const win32 = @import("win32");

const Allocator = std.mem.Allocator;

pub const Event = @import("Event.zig");

const HANDLE = win32.foundation.HANDLE;
const INVALID_HANDLE_VALUE = win32.foundation.INVALID_HANDLE_VALUE;
