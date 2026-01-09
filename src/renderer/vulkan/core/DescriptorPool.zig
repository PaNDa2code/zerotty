const DescriptorPool = @This();

context: *const Context,

handle: vk.DescriptorPool,

pub const Builder = DescriptorPoolBuilder(&.{});

fn DescriptorPoolBuilder(comptime Sizes: []const vk.DescriptorPoolSize) type {
    return struct {
        pub fn addPoolSize(
            comptime d_type: vk.DescriptorType,
            comptime d_count: comptime_int,
        ) type {
            return DescriptorPoolBuilder(Sizes ++ &[_]vk.DescriptorPoolSize{.{ .type = d_type, .descriptor_count = d_count }});
        }

        pub fn build(context: *const Context) InitError!DescriptorPool {
            return init(context, Sizes);
        }
    };
}

pub const InitError = vk.DeviceWrapper.CreateDescriptorPoolError;

pub fn init(
    context: *const Context,
    pool_sizes: []const vk.DescriptorPoolSize,
) InitError!DescriptorPool {
    const descript_pool_info = vk.DescriptorPoolCreateInfo{
        .max_sets = 1,
        .pool_size_count = @intCast(pool_sizes.len),
        .p_pool_sizes = pool_sizes.ptr,
    };

    const pool = try context.vkd.createDescriptorPool(
        context.device,
        &descript_pool_info,
        context.vk_allocator,
    );

    return .{
        .context = context,
        .handle = pool,
    };
}

pub fn deinit(self: *const DescriptorPool) void {
    self.context.vkd.destroyDescriptorPool(
        self.context.device,
        self.handle,
        self.context.vk_allocator,
    );
}

pub const AllocDescriptorError = vk.DeviceWrapper.AllocateDescriptorSetsError;

pub fn allocDescriptorSets(
    self: *const DescriptorPool,
    descriptor_set_layout: *const DescriptorSetLayout,
) AllocDescriptorError!vk.DescriptorSet {
    const descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.handle,
        .descriptor_set_count = 1,
        .p_set_layouts = &.{descriptor_set_layout.handle},
    };

    var descriptor_set = vk.DescriptorSet.null_handle;

    try self.context.vkd.allocateDescriptorSets(
        self.context.device,
        &descriptor_set_alloc_info,
        @ptrCast(&descriptor_set),
    );

    return descriptor_set;
}

pub const FreeDescriptorSetError = vk.DeviceWrapper.FreeDescriptorSetsError;

pub fn freeDescriptorSet(self: *const DescriptorPool, descriptor_set: vk.DescriptorSet) FreeDescriptorSetError!void {
    try self.context.vkd.freeDescriptorSets(
        self.context.device,
        self.handle,
        1,
        @ptrCast(&descriptor_set),
    );
}

const std = @import("std");
const vk = @import("vulkan");
const Context = @import("Context.zig");
const DescriptorSetLayout = @import("DescriptorSetLayout.zig");
