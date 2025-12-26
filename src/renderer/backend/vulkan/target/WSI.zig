const WSI = @This();

context: *const Context,

surface: vk.SurfaceKHR,
swap_chain: vk.SwapchainKHR,

images: []vk.Image,
image_views: []vk.ImageView,

extent: vk.Extent2D,
image_format: vk.Format,

// synchronization objects
inflight_fences: []vk.Fence,
render_finished_sems: []vk.Semaphore,
image_avilable_sems: []vk.Semaphore,

pub fn create(
    allocator: std.mem.Allocator,
    context: *const Context,
    surface: *const Interface.WsiSurface,
) !*WSI {
    const self = try allocator.create(WSI);
    errdefer allocator.destroy(self);

    self.context = context;
    self.surface = surface.handle;
    self.extent = surface.extent;

    return self;
}

pub fn destroy(self: *WSI, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

pub fn createWindowSurface(
    vki: *const vk.InstanceWrapper,
    instance: vk.Instance,
    window: *const Window,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.SurfaceKHR {
    switch (build_options.@"window-system") {
        .win32 => {
            const surface_info: vk.Win32SurfaceCreateInfoKHR = .{
                .hwnd = @ptrCast(window.hwnd),
                .hinstance = window.h_instance,
            };
            return vki.createWin32SurfaceKHR(instance, &surface_info, vk_mem_cb);
        },
        .xlib => {
            const surface_info: vk.XlibSurfaceCreateInfoKHR = .{
                .window = window.w,
                .dpy = @ptrCast(window.display),
            };
            return vki.createXlibSurfaceKHR(instance, &surface_info, vk_mem_cb);
        },
        .xcb => {
            const surface_info: vk.XcbSurfaceCreateInfoKHR = .{
                .connection = @ptrCast(window.connection),
                .window = window.window,
            };
            return vki.createXcbSurfaceKHR(instance, &surface_info, vk_mem_cb);
        },
        .glfw => {
            var surface: vk.SurfaceKHR = .null_handle;

            const res = c.glfwCreateWindowSurface(
                @ptrFromInt(@intFromEnum(instance)),
                @ptrCast(window.window),
                @ptrCast(vk_mem_cb),
                @ptrCast(&surface),
            );

            if (res != 0) {
                return error.GLFWSurfaceCreationFailed;
            }

            return surface;
        },
    }
}

pub fn instanceExtensions() []const [*:0]const u8 {
    return &[_][*:0]const u8{
        "VK_KHR_surface",
    } ++ switch (build_options.@"window-system") {
        .win32 => [_][*:0]const u8{"VK_KHR_win32_surface"},
        .xcb => [_][*:0]const u8{"VK_KHR_xcb_surface"},
        .xlib => [_][*:0]const u8{"VK_KHR_xlib_surface"},
        .glfw => {
            var count: u32 = 0;
            const extentions: [*]const [*:0]const u8 =
                @ptrCast(c.glfwGetRequiredInstanceExtensions(&count));

            return extentions[0..count];
        },
    };
}

pub fn deviceExtensions() []const [*:0]const u8 {
    return &.{
        "VK_KHR_swapchain",
    };
}

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});

pub const vtable = Interface.VTable{
    .create = create,
    .destroy = destroy,

    .instanceExtensions = instanceExtensions,
    .deviceExtensions = deviceExtensions,
};

const std = @import("std");
const vk = @import("vulkan");
const builtin = @import("builtin");
const build_options = @import("build_options");

const Interface = @import("Interface.zig");
const Context = @import("../core/Context.zig");
const Window = @import("../../../../window/root.zig").Window;
