const std = @import("std");
const vk = @import("vulkan");

const build_options = @import("build_options");

const Instance = @import("core/Instance.zig");

pub const SurfaceCreationInfo = union {
    win32: struct {
        hwnd: *anyopaque,
        hinstance: *anyopaque,
    },
    xcb: struct {
        connection: *anyopaque,
        window: u32,
    },
    xlib: struct {
        window: c_ulong,
        dpy: *anyopaque,
    },
    glfw: struct {
        window: *anyopaque,
    },

    pub fn fromWindow(window: anytype) SurfaceCreationInfo {
        return switch (@TypeOf(window.*).system) {
            .Win32 => .{
                .win32 = .{ .hwnd = @ptrCast(window.hwnd), .hinstance = @ptrCast(window.h_instance) },
            },
            .Xcb => .{
                .xcb = .{ .connection = @ptrCast(window.connection), .window = @intCast(window.window) },
            },
            .Xlib => .{
                .xlib = .{ .window = window.w, .dpy = @ptrCast(window.display) },
            },
            .GLFW => .{
                .glfw = .{
                    .window = @ptrCast(window.window),
                },
            },
            else => @compileError("Not handled"),
        };
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
};

pub fn createWindowSurface(
    instance: *const Instance,
    surface_creation_info: SurfaceCreationInfo,
) !vk.SurfaceKHR {
    switch (build_options.@"window-system") {
        .win32 => {
            const surface_info = vk.Win32SurfaceCreateInfoKHR{
                .hwnd = @ptrCast(surface_creation_info.win32.hwnd),
                .hinstance = @ptrCast(surface_creation_info.win32.hinstance),
            };
            return instance.vki.createWin32SurfaceKHR(instance.handle, &surface_info, instance.vk_allocator);
        },
        .xcb => {
            const surface_info = vk.XcbSurfaceCreateInfoKHR{
                .connection = @ptrCast(surface_creation_info.xcb.connection),
                .window = @intCast(surface_creation_info.xcb.window),
            };
            return instance.vki.createXcbSurfaceKHR(instance.handle, &surface_info, instance.vk_allocator);
        },
        .xlib => {
            const surface_info = vk.XlibSurfaceCreateInfoKHR{
                .window = surface_creation_info.xlib.window,
                .dpy = @ptrCast(surface_creation_info.xlib.dpy),
            };
            return instance.vki.createXlibSurfaceKHR(instance.handle, &surface_info, instance.vk_allocator);
        },
        .glfw => {
            var surface: vk.SurfaceKHR = .null_handle;

            _ = c.glfwCreateWindowSurface(
                @ptrFromInt(@intFromEnum(instance.handle)),
                @ptrCast(surface_creation_info.glfw.window),
                @ptrCast(instance.vk_allocator),
                @ptrCast(&surface),
            );

            return surface;
        },
    }
}

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});
