const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const build_options = @import("build_options");

const VulkanRenderer = @import("Vulkan.zig");

const log = VulkanRenderer.log;

pub fn pickPhysicalDevicesAlloc(
    self: *VulkanRenderer,
    allocator: Allocator,
    physical_devices: *[]vk.PhysicalDevice,
    queue_families_indices: *[]QueueFamilyIndices,
) !void {
    const _physical_devices = try self.instance_wrapper.enumeratePhysicalDevicesAlloc(self.instance, allocator);
    defer allocator.free(_physical_devices);

    // sort physical devices pased on score
    std.sort.heap(vk.PhysicalDevice, _physical_devices, self.instance_wrapper, physicalDeviceGt);

    var comptable_physical_devices = try std.ArrayList(vk.PhysicalDevice).initCapacity(allocator, 1);
    var _queue_families_indices = try std.ArrayList(QueueFamilyIndices).initCapacity(allocator, 1);

    for (_physical_devices) |physical_device| {
        const indices = try findQueueFamilies(self.instance_wrapper, physical_device, self.surface, allocator);
        if (indices) |ind| {
            try comptable_physical_devices.append(allocator, physical_device);
            try _queue_families_indices.append(allocator, ind);
        }
    }

    for (_physical_devices, 0..) |pd, i| {
        const props = self.instance_wrapper.getPhysicalDeviceProperties(pd);
        const deriver_version: vk.Version = @bitCast(props.driver_version);
        log.info(
            "GPU{}: {s} - {s} ({}.{}.{}.{})",
            .{
                i,
                props.device_name,
                @tagName(props.device_type),
                deriver_version.major,
                deriver_version.minor,
                deriver_version.patch,
                deriver_version.variant,
            },
        );
    }

    physical_devices.* = try comptable_physical_devices.toOwnedSlice(allocator);
    queue_families_indices.* = try _queue_families_indices.toOwnedSlice(allocator);
}

fn physicalDeviceScore(vki: *const vk.InstanceWrapper, physical_device: vk.PhysicalDevice) u32 {
    var score: u32 = 0;
    const device_props = vki.getPhysicalDeviceProperties(physical_device);
    switch (device_props.device_type) {
        .discrete_gpu => score += 2_000,
        .integrated_gpu => score += 1_000,
        else => {},
    }
    score += device_props.limits.max_image_dimension_2d;

    return score;
}

fn physicalDeviceGt(vki: *const vk.InstanceWrapper, a: vk.PhysicalDevice, b: vk.PhysicalDevice) bool {
    return physicalDeviceScore(vki, a) > physicalDeviceScore(vki, b);
}

fn isDeviceSuitable(vki: *const vk.InstanceWrapper, dev: vk.PhysicalDevice, allocator: Allocator) !bool {
    const indices = try findQueueFamilies(vki, dev, allocator);
    return indices.isComplite();
}

pub const QueueFamilyIndices = struct {
    graphics_family: u32,
    present_family: u32,
};

fn findQueueFamilies(
    vki: *const vk.InstanceWrapper,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: Allocator,
) !?QueueFamilyIndices {
    const queue_families = try vki.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator);
    defer allocator.free(queue_families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (queue_families, 0..) |*q, i| {
        if (q.queue_flags.graphics_bit)
            graphics_family = @intCast(i);

        const surface_support = try vki.getPhysicalDeviceSurfaceSupportKHR(
            physical_device,
            @intCast(i),
            surface,
        );

        if (surface_support == .true)
            present_family = @intCast(i);

        if (graphics_family != null and present_family != null)
            return .{
                .graphics_family = graphics_family.?,
                .present_family = present_family.?,
            };
    }

    return null;
}
