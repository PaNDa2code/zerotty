const std = @import("std");
const vk = @import("vulkan");
const core = @import("../core/root.zig");

pub const CommandBufferState = enum { recording, executable };
pub const CommandBufferType = enum { primary, secondary };

const Handle = enum(u32) { invalid = std.math.maxInt(u32), _ };

pub const CommandBufferRegistry = struct {
    const Self = @This();

    const ThreadContext = struct {
        pool: vk.CommandPool,
        command_buffers: []vk.CommandBuffer = &.{},
    };

    allocator: std.mem.Allocator,
    device: *const core.Device,

    mutex: std.Thread.Mutex = .{},

    thread_ids: []std.Thread.Id = &.{},
    threads: []ThreadContext = &.{},

    pub fn init(device: *const core.Device, allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.threads) |thread| {
            self.device.vkd.destroyCommandPool(
                self.device.handle,
                thread.pool,
                self.device.vk_allocator,
            );

            self.allocator.free(thread.command_buffers);
        }

        self.allocator.free(self.threads);
        self.allocator.free(self.thread_ids);
    }

    fn findThreadContextPtr(self: *Self) ?*ThreadContext {
        const current_thread_id = std.Thread.getCurrentId();

        for (self.thread_ids, 0..) |thread_id, i| {
            if (current_thread_id == thread_id)
                return &self.threads[i];
        }

        return null;
    }

    fn getThreadContextPtr(self: *Self) !*ThreadContext {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.findThreadContextPtr()) |ptr|
            return ptr;

        self.threads = try self.allocator.realloc(
            self.threads,
            self.threads.len + 1,
        );

        self.thread_ids = try self.allocator.realloc(
            self.thread_ids,
            self.thread_ids.len + 1,
        );

        self.threads[self.threads.len - 1].pool =
            try self.device.vkd.createCommandPool(
                self.device.handle,
                &vk.CommandPoolCreateInfo{
                    .queue_family_index = self.device
                        .physical_device.graphic_family_index,
                },
                self.device.vk_allocator,
            );

        self.threads[self.threads.len - 1].command_buffers = &.{};
        self.thread_ids[self.thread_ids.len - 1] = std.Thread.getCurrentId();

        return &self.threads[self.threads.len - 1];
    }

    fn createRaw(
        self: *Self,
        buffer_type: CommandBufferType,
    ) !Handle {
        const thread_context_ptr = try self.getThreadContextPtr();
        const index = thread_context_ptr.command_buffers.len;

        thread_context_ptr.command_buffers =
            try self.allocator.realloc(
                thread_context_ptr.command_buffers,
                index + 1,
            );

        try self.device.vkd.allocateCommandBuffers(
            self.device.handle,
            &vk.CommandBufferAllocateInfo{
                .command_buffer_count = 1,
                .command_pool = thread_context_ptr.pool,
                .level = if (buffer_type == .primary)
                    .primary
                else
                    .secondary,
            },
            thread_context_ptr.command_buffers[index .. index + 1].ptr,
        );

        return @enumFromInt(index);
    }

    pub fn create(
        self: *Self,
        comptime buffer_type: CommandBufferType,
    ) !CommandBuffer(.executable, buffer_type) {
        const handle = try self.createRaw(buffer_type);
        return .{ .handle = handle };
    }

    pub fn getVkHandle(self: *Self, cmd: anytype) !vk.CommandBuffer {
        const thread_context_ptr =
            self.findThreadContextPtr() orelse return error.NoThreadContext;

        return thread_context_ptr.command_buffers[@intFromEnum(cmd.handle)];
    }

    pub fn begin(
        self: *Self,
        cmd: anytype, // *CommandBuffer(state, type)
        flags: vk.CommandBufferUsageFlags,
    ) !CommandBuffer(.recording, @TypeOf(cmd.*).type) {
        if (@typeInfo(@TypeOf(cmd)) != .pointer)
            @compileError("You need to pass a pointer to a CommandBuffer.");
        if (@TypeOf(cmd.*).state != .executable)
            @compileError("You can only begin() a CommandBuffer that is in the .executable state.");
        if (cmd.handle == .invalid)
            return error.InvalidHandle;

        const vk_handle = try self.getVkHandle(cmd);
        const begin_info = vk.CommandBufferBeginInfo{ .flags = flags };
        try self.device.vkd.beginCommandBuffer(vk_handle, &begin_info);

        return .{ .handle = cmd.move().handle };
    }

    pub fn end(
        self: *Self,
        cmd: anytype, // CommandBuffer(state, type)
    ) !CommandBuffer(.executable, @TypeOf(cmd.*).type) {
        if (@typeInfo(@TypeOf(cmd)) != .pointer)
            @compileError("You need to pass a pointer to a CommandBuffer.");
        if (@TypeOf(cmd.*).state != .recording)
            @compileError("You can only end() a CommandBuffer that is in the .recording state.");
        if (cmd.handle == .invalid)
            return error.InvalidHandle;

        const vk_handle = try self.getVkHandle(cmd);
        try self.device.vkd.endCommandBuffer(vk_handle);

        return .{ .handle = cmd.handle };
    }
};

// typesafety to make sure command buffers are not submited while recording
// and no recording when ended
pub fn CommandBuffer(
    comptime buffer_state: CommandBufferState,
    comptime buffer_type: CommandBufferType,
) type {
    return struct {
        const Self = @This();
        pub const state = buffer_state;
        pub const @"type" = buffer_type;

        handle: Handle,

        pub fn move(self: *Self) Self {
            defer self.handle = .invalid;
            return .{ .handle = self.handle };
        }
    };
}

pub fn PrimaryCommandBuffer(
    comptime buffer_state: CommandBufferState,
) type {
    return CommandBuffer(buffer_state, .primary);
}

pub fn SecondaryCommandBuffer(
    comptime buffer_state: CommandBufferState,
) type {
    return CommandBuffer(buffer_state, .secondary);
}

test CommandBuffer {
    const testing = @import("../testing.zig");
    const device = try testing.getTestDeviceLocked();
    defer testing.unlockTestDevice();

    var registry = CommandBufferRegistry.init(
        device,
        std.testing.allocator,
    );
    defer registry.deinit();

    var cmd_buffer = try registry.create(.primary);
    var recording_cmd = try registry.begin(&cmd_buffer, .{});
    // cmd_buffer is now not usable
    //
    // ...
    //
    cmd_buffer = try registry.end(&recording_cmd);
}
