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
event_pool: []Event,
free_events: std.ArrayList(usize),

pub fn init(allocator: std.mem.Allocator, max_events: usize) !EventLoop {
    const event_pool = try allocator.alloc(Event, max_events);
    errdefer allocator.free(event_pool);

    var free_events = try std.ArrayList(usize).initCapacity(allocator, max_events);

    for (0..max_events) |i|
        free_events.appendAssumeCapacity(i);

    var backend_context: BackendContext = undefined;
    try backend_context.setup();

    return .{
        .backend_context = backend_context,
        .event_pool = event_pool,
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

pub fn allocEvent(self: *EventLoop) !*Event {
    const ev_idx = self.free_events.pop() orelse return error.ReachedMaxEvents;
    const event_ptr = &self.event_pool[ev_idx];
    event_ptr.status = .reserved;
    return event_ptr;
}

pub fn freeEvent(self: *EventLoop, event: *Event) void {
    event.status = .none;
    self.free_events.appendAssumeCapacity(
        (@intFromPtr(event) - @intFromPtr(self.event_pool.ptr)) / @sizeOf(Event),
    );
}

pub fn submitEvent(self: *EventLoop, event: *Event) !void {
    try self.backend_context.register(&event.request);
    try self.backend_context.queue(&event.request);
    try self.backend_context.submit();
}

pub fn poll(self: *EventLoop, timeout_ms: u32) !void {
    var res: i32 = 0;
    const completed_req = (try self.backend_context.dequeue_timeout(timeout_ms, &res)) orelse return;
    const event: *Event = @fieldParentPtr("request", @constCast(completed_req));

    if (event.completion_callback) |cb| {
        switch (cb(event, @intCast(res), event.user_data)) {
            .destroy => {
                self.free_events.appendAssumeCapacity(
                    (@intFromPtr(event) - @intFromPtr(self.event_pool.ptr)) / @sizeOf(Event),
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
    }
}

pub fn run(self: *EventLoop) !void {
    while (self.free_events.items.len < self.event_pool.len) {
        try self.poll(std.math.maxInt(u32));
    }
}

fn pushRequest(self: *EventLoop, req: Request, cb: anytype, user_data: ?*anyopaque) !*Event {
    const event_ptr = try self.allocEvent();

    event_ptr.request = req;
    event_ptr.completion_callback = cb;
    event_ptr.user_data = user_data;

    try self.backend_context.register(&event_ptr.request);

    return event_ptr;
}

fn pushAndRunRequest(self: *EventLoop, req: Request, cb: anytype, user_data: ?*anyopaque) !void {
    const event_ptr = try self.pushRequest(req, cb, user_data);
    try self.backend_context.queue(&event_ptr.request);
    try self.backend_context.submit();
}

pub fn deinit(self: *EventLoop, allocator: std.mem.Allocator) void {
    allocator.free(self.event_pool);
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

    // var fds: [2]std.c.fd_t = undefined;
    // _ = std.c.pipe(&fds);
    //
    // defer {
    //     _ = std.c.close(fds[0]);
    //     _ = std.c.close(fds[1]);
    // }
    //
    // const read_file = std.fs.File{ .handle = fds[0] };
    // const write_file = std.fs.File{ .handle = fds[1] };
    //
    // var read_buf: [5]u8 = undefined;
    //
    // try loop.write(write_file, "hello", write_cb, null);
    // try loop.read(read_file, read_buf[0..], read_cb, null);
    //
    // try loop.run();
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
