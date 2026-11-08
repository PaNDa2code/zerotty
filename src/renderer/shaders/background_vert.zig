const std = @import("std");

export fn main() callconv(.spirv_vertex) void {
    const position: @Vector(2, f32) = @floatFromInt(
        @Vector(2, u32){
            (std.spirv.vertex_index << 1) & 2,
            std.spirv.vertex_index & 2,
        },
    );

    const scale: @Vector(2, f32) = @splat(2.0);
    const offset: @Vector(2, f32) = @splat(1.0);

    const normlized = position * scale - offset;

    std.spirv.position_out.* = .{ normlized[0], normlized[1], 0.0, 1.0 };
}

