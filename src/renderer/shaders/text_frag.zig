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

const texture_index = @extern(*addrspace(.input) const u32, .{
    .name = "texture_index",
    .decoration = .{ .flat = 0 },
});

const texture_coords = @extern(*addrspace(.input) const @Vector(2, f32), .{
    .name = "texture_coords",
    .decoration = .{ .location = 1 },
});

const fg_color = @extern(*addrspace(.input) const @Vector(4, f32), .{
    .name = "fg_color",
    .decoration = .{ .location = 2 },
});

// const bg_color = @extern(*const addrspace(.input) @Vector(4, f32), .{
//     .name = "bg_color",
//     .decoration = .{ .location = 3 },
// });

const frag_color = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "frag_color",
    .decoration = .{ .location = 0 },
});

const textures = @extern(*addrspace(.constant) const @SpirvType(.{ .runtime_array = Sampler2D }), .{
    .name = "textures",
    .decoration = .{
        .descriptor = .{ .set = 1, .binding = 0 },
    },
});

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    const coverage: f32 = std.spirv.imageSampleImplicitLod(&textures.*[texture_index.*], texture_coords.*)[0];
    const alpha: f32 = fg_color[3] * coverage;

    frag_color.* = .{
        fg_color.*[0] * alpha,
        fg_color.*[1] * alpha,
        fg_color.*[2] * alpha,
        alpha,
    };
}
