const std = @import("std");

const Image2D = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = f32 },
    .format = .unknown,
    .dim = .@"2d",
    .depth = .unknown,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });

const Sampler2D = @SpirvType(.{ .sampled_image = Image2D });

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

const u_cell_colors = @extern(*addrspace(.constant) const Sampler2D, .{
    .name = "u_cell_colors",
    .decoration = .{
        .descriptor = .{ .set = 0, .binding = 1 },
    },
});

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    const cell: @Vector(2, u32) = .{
        @trunc(std.spirv.frag_coord[0] * ubo.cell_size_inv[0]),
        @trunc(std.spirv.frag_coord[1] * ubo.cell_size_inv[1]),
    };

    if (cell[0] >= ubo.grid_size[0] or cell[1] >= ubo.grid_size[1]) {
        frag_color.* = .{
            ubo.bg_color[0] * ubo.bg_color[3],
            ubo.bg_color[1] * ubo.bg_color[3],
            ubo.bg_color[2] * ubo.bg_color[3],
            ubo.bg_color[3],
        };

        return;
    }

    const color = texelFetch(u_cell_colors, cell, 0);

    frag_color.* = .{
        color[0] * color[3],
        color[1] * color[3],
        color[2] * color[3],
        color[3],
    };
}

inline fn texelFetch(sampled_image: anytype, coord: @Vector(2, u32), lod: u32) @Vector(4, f32) {
    const SampledImage = switch (@typeInfo(@TypeOf(sampled_image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to a sampled image"),
    };

    const Image = switch (@typeInfo(SampledImage)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |image| image,
            else => @compileError("expected a sampled image type"),
        },
        else => @compileError("expected a sampled image type"),
    };

    return asm volatile (
        \\%loaded_sampled_image = OpLoad %SampledImage %sampled_image
        \\%image = OpImage %Image %loaded_sampled_image
        \\%ret = OpImageFetch %Vec4 %image %coord Lod %lod
        : [ret] "" (-> @Vector(4, f32)),
        : [SampledImage] "t" (SampledImage),
          [Image] "t" (Image),
          [Vec4] "t" (@Vector(4, f32)),
          [sampled_image] "" (sampled_image),
          [coord] "" (coord),
          [lod] "" (lod),
    );
}
