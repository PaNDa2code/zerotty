const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const build_options = @import("build_options");

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub fn createInstance(
    vkb: *const vk.BaseWrapper,
    allocator: Allocator,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.Instance {
    const app_info = vk.ApplicationInfo{
        .p_application_name = "zerotty",

        .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .api_version = @bitCast(vk.API_VERSION_1_4),

        .engine_version = 0,
    };

    if (build_options.@"renderer-debug" and
        !try @import("debug.zig")
            .checkValidationLayerSupport(vkb, allocator))
        @panic("Validation layer is not supported");

    const validation_layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    const layers = [_][*:0]const u8{} ++
        if (build_options.@"renderer-debug") validation_layers else [_][*:0]const u8{};

    const win32_exts = [_][*:0]const u8{
        "VK_KHR_win32_surface",
    };

    const xlib_exts = [_][*:0]const u8{
        "VK_KHR_xlib_surface",
    };

    const xcb_exts = [_][*:0]const u8{
        "VK_KHR_xcb_surface",
    };

    const comptime_extensions = [_][*:0]const u8{
        "VK_KHR_surface",
    } ++ switch (build_options.@"window-system") {
        .win32 => win32_exts,
        .xlib => xlib_exts,
        .xcb => xcb_exts,
        .glfw => .{},
    } ++ if (build_options.@"renderer-debug")
        .{"VK_EXT_debug_utils"}
    else
        .{};

    const runtime_extensions: [][*:0]const u8 = if (build_options.@"window-system" == .glfw) blk: {
        var count: u32 = 0;
        const glfw_exts =
            @as(?[*][*:0]const u8, @ptrCast(c.glfwGetRequiredInstanceExtensions(&count))) orelse
            @panic("can't get glfw requred extensions");
        break :blk glfw_exts[0..@intCast(count)];
    } else &.{};

    const slices = [_][]const [*:0]const u8{ &comptime_extensions, runtime_extensions };

    const extensions =
        try std.mem.concatMaybeSentinel(
            allocator,
            [*:0]const u8,
            &slices,
            null,
        );

    defer allocator.free(extensions);

    const inst_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = layers.len,
        .pp_enabled_layer_names = &layers,
    };

    return vkb.createInstance(&inst_info, vk_mem_cb);
}
