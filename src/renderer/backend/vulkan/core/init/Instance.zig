//! Temporary Vulkan instance used during setup.
const Instance = @This();

handle: vk.Instance,

version: vk.Version,

vkb: vk.BaseWrapper,
vki: vk.InstanceWrapper,

vk_allocator: *const vk.AllocationCallbacks,

debug_messenger: if (builtin.mode == .Debug) vk.DebugUtilsMessengerEXT else void,

pub const InitError = std.mem.Allocator.Error ||
    vk.BaseWrapper.CreateInstanceError ||
    debug.DebugMessagerError ||
    debug.CheckValidationLayerSupportError;

pub fn init(
    allocator: std.mem.Allocator,
    vk_allocator: *const vk.AllocationCallbacks,
    required_extensions: []const [*:0]const u8,
) InitError!Instance {
    const vkb = vk.BaseWrapper.load(struct {
        const vk_lib_path: [*:0]const u8 = switch (builtin.os.tag) {
            .windows => "C:\\Windows\\System32\\vulkan-1.dll",
            .linux => "libvulkan.so.1",
            else => {},
        };

        pub fn load(_: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction {
            var lib = std.DynLib.openZ(vk_lib_path) catch unreachable;
            const symbol = lib.lookup(*anyopaque, std.mem.span(procname));
            return @ptrCast(symbol);
        }
    }.load);

    const debug_extentions = [_][*:0]const u8{
        "VK_EXT_debug_utils",
    };

    const validation_layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    const slices = [_][]const [*:0]const u8{
        required_extensions,
    } ++ if (builtin.mode == .Debug) [_][]const [*:0]const u8{&debug_extentions} else .{};

    const extensions = try std.mem.concatMaybeSentinel(allocator, [*:0]const u8, &slices, null);
    defer allocator.free(extensions);

    const validation_layers_supported = try debug.checkValidationLayerSupport(&vkb, allocator);

    const layers: []const [*:0]const u8 =
        if (builtin.mode == .Debug and validation_layers_supported)
            validation_layers[0..]
        else
            &.{};

    const api_version: u32 = blk: {
        if (vkb.dispatch.vkEnumerateInstanceVersion == null)
            break :blk @bitCast(vk.API_VERSION_1_0);

        break :blk vkb.enumerateInstanceVersion() catch @bitCast(vk.API_VERSION_1_0);
    };

    const instance_info = vk.InstanceCreateInfo{
        .p_application_info = &.{
            .p_application_name = "zerotty",

            .application_version = 0,
            .api_version = api_version,

            .engine_version = 0,
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,

        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
    };

    const handle = try vkb.createInstance(&instance_info, vk_allocator);

    const vki = vk.InstanceWrapper.load(
        handle,
        vkb.dispatch.vkGetInstanceProcAddr.?,
    );

    const debug_messenger = if (builtin.mode == .Debug)
        try debug.debugMessenger(
            &vki,
            handle,
            vk_allocator,
        )
    else {};

    return .{
        .handle = handle,
        .version = @bitCast(api_version),
        .vkb = vkb,
        .vki = vki,
        .vk_allocator = vk_allocator,
        .debug_messenger = debug_messenger,
    };
}

pub fn deinit(self: *const Instance) void {
    if (builtin.mode == .Debug)
        self.vki.destroyDebugUtilsMessengerEXT(
            self.handle,
            self.debug_messenger,
            self.vk_allocator,
        );

    self.vki.destroyInstance(self.handle, self.vk_allocator);
}

const std = @import("std");
const vk = @import("vulkan");
const builtin = @import("builtin");

const debug = @import("debug.zig");
