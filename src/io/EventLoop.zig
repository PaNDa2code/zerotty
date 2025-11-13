const EventLoop = @This();

pub const Callback = *const fn (*Event, usize, ?*anyopaque) CallbackAction;

pub const CallbackAction = enum {
    keep,
    retry,
    destroy,
};

pub const Event = struct {
    pub const Status = enum { reserved, running, none };

    request: Request,
    status: Status = .none,
    completion_callback: ?Callback = null,
    user_data: ?*anyopaque = null,
};

backend_context: BackendContext,
event_queue: []Event,
free_events: std.ArrayList(usize),

pub fn init(allocator: std.mem.Allocator, max_events: usize) !EventLoop {
    const event_queue = try allocator.alloc(Event, max_events);
    errdefer allocator.free(event_queue);

    var free_events = try std.ArrayList(usize).initCapacity(allocator, max_events);

    for (0..max_events) |i|
        free_events.appendAssumeCapacity(i);

    var backend_context: BackendContext = undefined;
    try backend_context.setup();

    return .{
        .backend_context = backend_context,
        .event_queue = event_queue,
        .free_events = free_events,
    };
}

pub fn read(
    self: *EventLoop,
    file: std.fs.File,
    buf: []u8,
    completion_callback: ?Callback,
    user_data: ?*anyopaque,
) !void {
    try self.pushAndRunRequest(.{
        .handle = file.handle,
        .op_data = .{ .read = buf },
    }, completion_callback, user_data);
}

pub fn write(
    self: *EventLoop,
    file: std.fs.File,
    buf: []const u8,
    completion_callback: ?Callback,
    user_data: ?*anyopaque,
) !void {
    try self.pushAndRunRequest(.{
        .handle = file.handle,
        .op_data = .{ .write = buf },
    }, completion_callback, user_data);
}

pub fn poll(self: *EventLoop) !void {
    var res: i32 = 0;
    const completed_req = (try self.backend_context.dequeue_timeout(0, &res)) orelse return;
    const event: *Event = @fieldParentPtr("request", @constCast(completed_req));

    if (event.completion_callback) |cb| {
        switch (cb(event, @intCast(res), event.user_data)) {
            .destroy => {
                self.free_events.appendAssumeCapacity(
                    (@intFromPtr(event) - @intFromPtr(self.event_queue.ptr)) / @sizeOf(Event),
                );
            },
            .keep => {
                event.status = .reserved;
            },
            .retry => {
                try self.backend_context.queue(completed_req);
                try self.backend_context.submit();
            },
        }
    } else {
        self.free_events.appendAssumeCapacity(
            (@intFromPtr(event) - @intFromPtr(self.event_queue.ptr)) / @sizeOf(Event),
        );
    }
}

pub fn run(self: *EventLoop) !void {
    while (self.free_events.items.len < self.event_queue.len) {
        try self.poll();
    }
}

inline fn pushAndRunRequest(self: *EventLoop, req: Request, cb: anytype, user_data: ?*anyopaque) !void {
    const ev_idx = self.free_events.pop() orelse return error.ReachedMaxEvents;
    self.event_queue[ev_idx].request = req;
    try self.backend_context.register(&self.event_queue[ev_idx].request);
    try self.backend_context.queue(&self.event_queue[ev_idx].request);
    try self.backend_context.submit();

    self.event_queue[ev_idx].completion_callback = cb;
    self.event_queue[ev_idx].user_data = user_data;
}

pub fn deinit(self: *EventLoop, allocator: std.mem.Allocator) void {
    allocator.free(self.event_queue);
    self.free_events.deinit(allocator);
}

const std = @import("std");
const root = @import("root.zig");
const builtin = @import("builtin");

const Request = root.Request;
const Operation = root.Operation;
const Result = root.Result;

const BackendContext = root.Backend.Context;

test "event loop basic pipe rw" {
    var loop = try EventLoop.init(std.testing.allocator, 8);
    defer loop.deinit(std.testing.allocator);

    var fds: [2]std.os.linux.fd_t = undefined;
    _ = std.os.linux.pipe(&fds);

    const read_file = std.fs.File{ .handle = fds[0] };
    const write_file = std.fs.File{ .handle = fds[1] };

    var read_buf: [5]u8 = undefined;

    try loop.write(write_file, "hello", write_cb, null);
    try loop.read(read_file, read_buf[0..], read_cb, null);

    try loop.run();
}

var counter: usize = 0;

fn read_cb(ev: *EventLoop.Event, _: usize, _: ?*anyopaque) EventLoop.CallbackAction {
    const buf = ev.request.op_data.read;
    std.testing.expectEqualStrings("hello", buf[0..5]) catch unreachable;

    if (counter >= 100)
        return .destroy;

    return .retry;
}

fn write_cb(_: *EventLoop.Event, _: usize, _: ?*anyopaque) EventLoop.CallbackAction {
    counter += 1;

    if (counter >= 100)
        return .destroy;

    return .retry;
}
