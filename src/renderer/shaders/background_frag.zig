const std = @import("std");
const spirv = @import("spirv.zig");

const ubo = @extern(*addrspace(.uniform) const extern struct {
    screen_to_clip_scale: @Vector(2, f32),
    screen_to_clip_offset: @Vector(2, f32),
    inv_atlas_size: @Vector(2, f32), // 1 / atlas_size
    cell_size: @Vector(2, f32),
    cell_size_inv: @Vector(2, f32),
    grid_size: @Vector(2, u32),
    bg_color: @Vector(4, f32),
    baseline: f32,
}, .{
    .name = "ubo",
    .decoration = .{
        .descriptor = .{ .set = 0, .binding = 0 },
    },
});

const frag_color = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "frag_color",
    .decoration = .{ .location = 0 },
});

const u_cell_colors = @extern(*addrspace(.constant) const spirv.Sampler2D, .{
    .name = "u_cell_colors",
    .decoration = .{
        .descriptor = .{ .set = 0, .binding = 1 },
    },
});

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    // frag_coord * (1 / cell_size) = cell_position
    const cell: @Vector(2, u32) = .{
        @trunc(std.spirv.frag_coord[0] * ubo.cell_size_inv[0]),
        @trunc(std.spirv.frag_coord[1] * ubo.cell_size_inv[1]),
    };

    // outside the logical grid, but could be a visiable point on the surface
    // so we fallback to the background color
    if (cell[0] >= ubo.grid_size[0] or cell[1] >= ubo.grid_size[1]) {
        frag_color.* = .{
            ubo.bg_color[0] * ubo.bg_color[3],
            ubo.bg_color[1] * ubo.bg_color[3],
            ubo.bg_color[2] * ubo.bg_color[3],
            ubo.bg_color[3],
        };

        return;
    }

    const color = spirv.texelFetch(u_cell_colors, cell, 0);

    frag_color.* = .{
        color[0] * color[3],
        color[1] * color[3],
        color[2] * color[3],
        color[3],
    };
}
