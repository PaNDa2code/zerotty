const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const build_options = @import("build_options");

const Window = @import("../../../window/root.zig").Window;

pub fn createWindowSurface(
    vki: *const vk.InstanceWrapper,
    instance: vk.Instance,
    window: *const Window,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.SurfaceKHR {
    switch (build_options.@"window-system") {
        .Win32 => {
            const surface_info: vk.Win32SurfaceCreateInfoKHR = .{
                .hwnd = @ptrCast(window.hwnd),
                .hinstance = window.h_instance,
            };
            return vki.createWin32SurfaceKHR(instance, &surface_info, vk_mem_cb);
        },
        .Xlib => {
            const surface_info: vk.XlibSurfaceCreateInfoKHR = .{
                .window = window.w,
                .dpy = @ptrCast(window.display),
            };
            return vki.createXlibSurfaceKHR(instance, &surface_info, vk_mem_cb);
        },
        .Xcb => {
            const surface_info: vk.XcbSurfaceCreateInfoKHR = .{
                .connection = @ptrCast(window.connection),
                .window = window.window,
            };
            return vki.createXcbSurfaceKHR(instance, &surface_info, vk_mem_cb);
        },
    }
}
