const std = @import("std");
const vk = @import("vulkan");

const log = std.log.scoped(.VulkanDebugUtils);

const VulkanRenderer = @import("../Vulkan.zig");

pub fn setupDebugMessenger(self: *VulkanRenderer) !void {
    self.debug_messenger = try debugMessenger(
        self.instance_wrapper,
        self.instance,
        &self.vk_mem.vkAllocatorCallbacks(),
    );
}

fn debugMessenger(
    vki: *const vk.InstanceWrapper,
    instance: vk.Instance,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.DebugUtilsMessengerEXT {
    if (vki.dispatch.vkCreateDebugUtilsMessengerEXT == null)
        @panic("createDebugUtilsMessengerEXT is null");

    const debug_utils_messenger_create_info = vk.DebugUtilsMessengerCreateInfoEXT{
        .message_severity = .{
            .verbose_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
            // .info_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = &debugCallback,
    };

    return vki.createDebugUtilsMessengerEXT(
        instance,
        &debug_utils_messenger_create_info,
        vk_mem_cb,
    );
}

fn logSev(
    comptime fmt: []const u8,
    args: anytype,
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
) void {
    if (message_severity.warning_bit_ext)
        log.warn(fmt, args)
    else if (message_severity.error_bit_ext)
        log.err(fmt, args)
    else
        log.info(fmt, args);
}

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    const message_type: Types =
        if (message_types.general_bit_ext)
            .general
        else if (message_types.validation_bit_ext)
            .validation
        else if (message_types.performance_bit_ext)
            .performance
        else
            unreachable;

    const debug_data = p_callback_data orelse return .false;

    logSev("[{s}] {?s}", .{
        @tagName(message_type),
        debug_data.p_message,
    }, message_severity);

    for (0..debug_data.object_count) |i| {
        const object_info = &debug_data.p_objects.?[i];
        logSev("\t- [{s}] 0x{x}", .{
            @tagName(object_info.object_type),
            object_info.object_handle,
        }, message_severity);
    }

    return .false;
}

const Types = enum {
    general,
    validation,
    performance,
    device_address_binding,
};

pub fn checkValidationLayerSupport(vkb: *const vk.BaseWrapper, allocator: std.mem.Allocator) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(allocator);
    defer allocator.free(available_layers);

    for (available_layers) |*layer| {
        const layer_name = std.mem.span(@as([*c]u8, &layer.layer_name));
        if (std.mem.eql(u8, layer_name, "VK_LAYER_KHRONOS_validation"))
            return true;
    }

    return false;
}
