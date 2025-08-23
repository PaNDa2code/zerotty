const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const build_options = @import("build_options");

const VulkanRenderer = @import("Vulkan.zig");

pub fn createInstance(self: *VulkanRenderer) !void {
    self.instance = try _createInstance(self.base_wrapper, self.vk_mem.allocator, &self.vk_mem.vkAllocatorCallbacks());
}

fn _createInstance(
    vkb: *const vk.BaseWrapper,
    allocator: Allocator,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.Instance {
    const app_info = vk.ApplicationInfo{
        .p_application_name = "zerotty",

        .application_version = 0,
        .api_version = @bitCast(vk.HEADER_VERSION_COMPLETE),

        // .p_engine_name = "no_engine",
        .engine_version = 0,
    };

    if (builtin.mode == .Debug and !try @import("debug.zig").checkValidationLayerSupport(vkb, allocator))
        @panic("Validation layer is not supported");

    const validation_layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    const win32_exts = [_][*:0]const u8{
        "VK_KHR_win32_surface",
    };

    const xlib_exts = [_][*:0]const u8{
        "VK_KHR_xlib_surface",
        "VK_EXT_acquire_xlib_display",
    };

    const xcb_exts = [_][*:0]const u8{
        "VK_KHR_xcb_surface",
    };

    const extensions = [_][*:0]const u8{
        "VK_KHR_surface",
        "VK_EXT_debug_utils",
    } ++ switch (build_options.@"window-system") {
        .Win32 => win32_exts,
        .Xlib => xlib_exts,
        .Xcb => xcb_exts,
    };

    const inst_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = extensions.len,
        .pp_enabled_extension_names = &extensions,
        .enabled_layer_count = if (builtin.mode == .Debug) validation_layers.len else 0,
        .pp_enabled_layer_names = if (builtin.mode == .Debug) &validation_layers else null,
    };

    return vkb.createInstance(&inst_info, vk_mem_cb);
}
