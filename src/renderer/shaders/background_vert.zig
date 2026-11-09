const std = @import("std");

export fn main() callconv(.spirv_vertex) void {
    const uv: @Vector(2, f32) = @floatFromInt(
        @Vector(2, u32){
            (std.spirv.vertex_index << 1) & 2,
            std.spirv.vertex_index & 2,
        },
    );

    std.spirv.position_out.* = .{
        uv[0] * 2.0 - 1.0,
        uv[1] * 2.0 - 1.0,
        0.0,
        1.0,
    };
}
