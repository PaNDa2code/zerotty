const std = @import("std");
const vk = @import("vulkan");

const log = std.log.scoped(.Vulkan);

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) vk.Bool32 {
    _ = p_user_data; // autofix
    _ = p_callback_data; // autofix
    _ = message_type; // autofix
    _ = message_severity; // autofix
}

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
