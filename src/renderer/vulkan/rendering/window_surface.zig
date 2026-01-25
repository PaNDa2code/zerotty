const std = @import("std");
const vk = @import("vulkan");

const build_options = @import("build_options");

const Instance = @import("../core/root.zig").Instance;

pub const SurfaceCreationInfo = union(enum) {
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
    headless: void,

    pub fn fromWindowHandles(handles: window.WindowHandles) SurfaceCreationInfo {
        return switch (window.Api) {
            .win32 => .{
                .win32 = .{ .hwnd = @ptrCast(handles.hwnd), .hinstance = @ptrCast(handles.h_instance) },
            },
            .xcb => .{
                .xcb = .{ .connection = @ptrCast(handles.connection), .window = @intCast(handles.window) },
            },
            .xlib => .{
                .xlib = .{ .window = handles.w, .dpy = @ptrCast(handles.display) },
            },
            .glfw => .{
                .glfw = .{
                    .window = @ptrCast(handles.window),
                },
            },
            // else => unreachable,
        };
    }

    pub fn instanceExtensionsAlloc(self: SurfaceCreationInfo, allocator: std.mem.Allocator) ![]const [*:0]const u8 {
        if (build_options.@"window-system" == .glfw) {
            var count: u32 = 0;
            const extentions: [*]const [*:0]const u8 =
                @ptrCast(c.glfwGetRequiredInstanceExtensions(&count));

            return extentions[0..count];
        }

        const exts = try allocator.alloc([*:0]const u8, 2);

        exts[0] = "VK_KHR_surface";

        exts[1] = switch (self) {
            .win32 => "VK_KHR_win32_surface",
            .xcb => "VK_KHR_xcb_surface",
            .xlib => "VK_KHR_xlib_surface",
            .headless => "VK_EXT_headless_surface",
            else => unreachable,
        };

        return exts;
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
    if (build_options.@"window-system" == .glfw) {
        var surface: vk.SurfaceKHR = .null_handle;

        _ = c.glfwCreateWindowSurface(
            @ptrFromInt(@intFromEnum(instance.handle)),
            @ptrCast(surface_creation_info.glfw.window),
            @ptrCast(instance.vk_allocator),
            @ptrCast(&surface),
        );

        return surface;
    }

    switch (surface_creation_info) {
        .win32 => |info| {
            const surface_info = vk.Win32SurfaceCreateInfoKHR{
                .hwnd = @ptrCast(info.hwnd),
                .hinstance = @ptrCast(info.hinstance),
            };
            return instance.vki.createWin32SurfaceKHR(instance.handle, &surface_info, instance.vk_allocator);
        },
        .xcb => |info| {
            const surface_info = vk.XcbSurfaceCreateInfoKHR{
                .connection = @ptrCast(info.connection),
                .window = @intCast(info.window),
            };
            return instance.vki.createXcbSurfaceKHR(instance.handle, &surface_info, instance.vk_allocator);
        },
        .xlib => |info| {
            const surface_info = vk.XlibSurfaceCreateInfoKHR{
                .window = info.window,
                .dpy = @ptrCast(info.dpy),
            };
            return instance.vki.createXlibSurfaceKHR(instance.handle, &surface_info, instance.vk_allocator);
        },
        .headless => {
            const surface_info = vk.HeadlessSurfaceCreateInfoEXT{};
            return instance.vki.createHeadlessSurfaceEXT(instance.handle, &surface_info, instance.vk_allocator);
        },
        else => unreachable,
    }
}

const window = @import("window");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});
