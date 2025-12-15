const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const build_options = @import("build_options");

const Window = @import("../../../../window/root.zig").Window;

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
                std.debug.panic("glfwCreateWindowSurface({},{},{},{}) returns {}", .{
                    @intFromEnum(instance),
                    window.window,
                    vk_mem_cb,
                    surface,
                    res,
                });
            }

            return surface;
        },
    }
}

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});
