const std = @import("std");
const vk = @import("vulkan");

const log = std.log.scoped(.Vulkan);

pub fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.C) vk.Bool32 {
    const t: Types =
        if (message_types.general_bit_ext)
            .general
        else if (message_types.validation_bit_ext)
            .validation
        else if (message_types.performance_bit_ext)
            .performance
        else if (message_types.performance_bit_ext)
            .device_address_binding
        else
            unreachable;

    const fmt_buf = "{s}: {?s}";
    const fmt_args = .{ @tagName(t), if (p_callback_data) |p| p.p_message else null };

    if (message_severity.verbose_bit_ext)
        log.debug(fmt_buf, fmt_args)
    else if (message_severity.info_bit_ext)
        log.info(fmt_buf, fmt_args)
    else if (message_severity.warning_bit_ext)
        log.warn(fmt_buf, fmt_args)
    else if (message_severity.error_bit_ext)
        log.err(fmt_buf, fmt_args);

    return vk.FALSE;
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
