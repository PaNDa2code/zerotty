pub const Api = @import("build_options").@"render-backend";

pub const Renderer = switch (Api) {
    .OpenGL => @import("opengl/OpenGL.zig"),
    .D3D11 => @import("d3d11/D3D11.zig"),
    .Vulkan => @import("vulkan/Vulkan.zig"),
};

pub const FPS = @import("FPS.zig");
