//! Abstract renderer interface implemented by backends 
//! [`OpenGLRenderer`](src/renderer/opengl/OpenGL.zig) or [`VulkanRenderer`](src/renderer/vulkan/Vulkan.zig)
const Renderer = @This();

backend: RendererBackend,
fps: FPS,
cursor: Cursor,

pub fn init(window: *Window, allocator: Allocator) !Renderer {
    const backend = try RendererBackend.init(window, allocator);
    var cursor = try Cursor.init();
    cursor.row_len = backend.grid.cols;
    return .{
        .backend = backend,
        .fps = try FPS.init(),
        .cursor = cursor,
    };
}

pub fn deinit(self: *Renderer) void {
    self.backend.deinit();
}

pub fn clearBuffer(self: *Renderer, color: ColorRGBAf32) void {
    self.backend.clearBuffer(color);
}

pub fn presentBuffer(self: *Renderer) void {
    self.backend.presentBuffer();
}

pub fn renaderGrid(self: *Renderer) void {
    self.backend.renaderGrid();
}

pub fn setCell(
    self: *Renderer,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    try self.backend.setCell(row, col, char_code, fg_color, bg_color);
}

pub fn setCursorCell(self: *Renderer, char_code: u32) !void {
    try self.setCell(self.cursor.row, self.cursor.col, char_code, null, null);
    self.cursor.nextCol();
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
pub const Cursor = @import("Cursor.zig");
const Window = @import("../window/root.zig").Window;
const Allocator = @import("std").mem.Allocator;
const ColorRGBAu8 = @import("common.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("common.zig").ColorRGBAf32;
