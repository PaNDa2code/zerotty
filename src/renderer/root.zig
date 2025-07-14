const Renderer = @This();

backend: RendererBackend,
fps: FPS,

pub fn init(window: *Window, allocator: Allocator) !Renderer {
    return .{
        .backend = try RendererBackend.init(window, allocator),
        .fps = try FPS.init(),
    };
}

pub fn deinit(self: *Renderer) void {
    self.backend.deinit();
}

pub fn clearBuffer(self: *Renderer, color: ColorRGBA) void {
    self.backend.clearBuffer(color);
}

pub fn presentBuffer(self: *Renderer) void {
    self.backend.presentBuffer();
}

pub fn renaderText(self: *Renderer, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    self.backend.renaderText(buffer, x, y, color);
}

pub fn resize(self: *Renderer, width: u32, height: u32) !void {
    return self.backend.resize(width, height);
}

pub fn getFps(self: *Renderer) f64 {
    return self.fps.getFps();
}

pub const Api = @import("build_options").@"render-backend";

pub const RendererBackend = switch (Api) {
    .OpenGL => @import("opengl/OpenGL.zig"),
    .D3D11 => @import("d3d11/D3D11.zig"),
    .Vulkan => @import("vulkan/Vulkan.zig"),
};

pub const FPS = @import("FPS.zig");
const Window = @import("../window/root.zig").Window;
const Allocator = @import("std").mem.Allocator;
const ColorRGBA = @import("common.zig").ColorRGBA;

