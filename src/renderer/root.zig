pub const RendererSettings = struct {
    surface_height: u32,
    surface_width: u32,
    grid_rows: u32,
    grid_cols: u32,
};

const OpenGLImpl = @import("OpenGL.zig");
const VulanImpl = @import("Vulkan.zig");

const genaric = @import("genaric.zig");

const Api = @import("build_options").@"render-backend";

const BackendImpl = switch (Api) {
    .opengl => OpenGLImpl,
    .vulkan => VulanImpl,
    .d3d11 => @compileError("D3D11 is deprecated"),
};

pub const Renderer = genaric.GenaricRenderer(BackendImpl);

pub const vertex = @import("vertex.zig");
