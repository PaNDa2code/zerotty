pub const RendererSettings = struct {
    surface_height: u32,
    surface_width: u32,
    grid_rows: u32,
    grid_cols: u32,
    cell_width: u32,
    cell_height: u32,
    baseline: i32 = 0,
};

pub const Renderer = @import("vulkan/Renderer.zig");

pub const vertex = @import("vertex.zig");
pub const spirv = @import("spirv.zig");

comptime {
    @import("std").testing.refAllDecls(@This());
}
