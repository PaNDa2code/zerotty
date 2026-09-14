const std = @import("std");
const gpu = std.gpu;

const Vec2 = @Vector(2, f32);
const Vec4 = @Vector(4, f32);
const UVec2 = @Vector(2, u32);

// zig fmt: off

const TextUniform = extern struct {
    screen_to_clip_scale:   Vec2,
    screen_to_clip_offset:  Vec2,
    inv_atlas_size:         Vec2, // 1 / atlas_size
    cell_size:              Vec2,
    baseline:               f32,
};


const ubo = uniform("ubo", TextUniform, 0, 0);

// Vertex input
const p_postion         = input("p_postion",        u32, 0);
const p_glyph_entry     = input("p_glyph_entry",    UVec2, 1);
const fg_color          = input("fg_color",         Vec4, 2);
const bg_color          = input("bg_color",         Vec4, 3);

// Vertex output
const f_texture_index   = output("f_texture_index", u32,  0);
const f_texture_coords  = output("f_texture_coords",Vec2, 1);
const f_fg_color        = output("f_fg_color",      Vec4, 2);
const f_bg_color        = output("f_bg_color",      Vec4, 3);
// zig fmt: on

export fn main() callconv(.spirv_vertex) void {
    asm volatile (
        \\OpDecorate %f_texture_index Flat
        :
        : [f_texture_index] "" (f_texture_index),
    );

    const vertex_index = gpu.vertex_index;

    const quad_position = Vec2{
        @floatFromInt(@intFromBool(1 <= vertex_index and vertex_index <= 3)),
        @floatFromInt(@intFromBool(2 <= vertex_index and vertex_index <= 4)),
    };

    const lo = p_glyph_entry.*[0];
    const hi = p_glyph_entry.*[1];

    const atlas_id = lo & 0xFF;
    const glyph_pos = Vec2{
        @floatFromInt((lo >> 8) & 0xFFF),
        @floatFromInt((lo >> 20) & 0xFFF),
    };
    const glyph_size = Vec2{
        @floatFromInt(hi & 0xFF),
        @floatFromInt((hi >> 8) & 0xFF),
    };
    const glyph_bearing = Vec2{
        @floatFromInt(@as(i32, @bitCast(((hi >> 16) & 0xFF) << 24)) >> 24),
        @floatFromInt(@as(i32, @bitCast(((hi >> 24) & 0xFF) << 24)) >> 24),
    };

    const row = p_postion.* & 0xFFFF;
    const col = (p_postion.* >> 16) & 0xFFFF;

    const cell_origin = Vec2{ @floatFromInt(col), @floatFromInt(row) } * ubo.cell_size;
    const glyph_offset = cell_origin + Vec2{ 0.0, ubo.baseline } + glyph_bearing;
    const vertex_position = glyph_offset + quad_position * glyph_size;

    const clip_position = vertex_position * ubo.screen_to_clip_scale + ubo.screen_to_clip_offset;

    gpu.position_out.* = .{ clip_position[0], clip_position[1], 0.0, 1.0 };

    f_texture_index.* = atlas_id;
    f_texture_coords.* = (glyph_pos + quad_position * glyph_size) * ubo.inv_atlas_size;
    f_fg_color.* = fg_color.*;
    f_bg_color.* = bg_color.*;
}

fn uniform(name: []const u8, T: type, set: u32, binding: u32) *addrspace(.uniform) const T {
    return @extern(*addrspace(.uniform) const T, .{
        .name = name,
        .decoration = .{
            .descriptor = .{ .set = set, .binding = binding },
        },
    });
}

fn input(name: []const u8, T: type, location: u32) *addrspace(.input) const T {
    return @extern(*addrspace(.input) const T, .{
        .name = name,
        .decoration = .{ .location = location },
    });
}

fn output(name: []const u8, T: type, location: u32) *addrspace(.output) T {
    return @extern(*addrspace(.output) T, .{
        .name = name,
        .decoration = .{ .location = location },
    });
}
