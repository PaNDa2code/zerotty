const std = @import("std");
const spirv = @import("spirv.zig");
const bitfieldExtractFromU32 = spirv.bitfieldExtractFromU32;

const ubo = @extern(*addrspace(.uniform) const extern struct {
    screen_to_clip_scale: @Vector(2, f32),
    screen_to_clip_offset: @Vector(2, f32),
    inv_atlas_size: @Vector(2, f32),
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

// Vertex input
const p_postion = @extern(*addrspace(.input) const u32, .{
    .name = "p_postion",
    .decoration = .{ .location = 0 },
});

const p_glyph_entry = @extern(*addrspace(.input) const @Vector(2, u32), .{
    .name = "p_glyph_entry",
    .decoration = .{ .location = 1 },
});

const fg_color = @extern(*addrspace(.input) const @Vector(4, f32), .{
    .name = "fg_color",
    .decoration = .{ .location = 2 },
});

const bg_color = @extern(*addrspace(.input) const @Vector(4, f32), .{
    .name = "bg_color",
    .decoration = .{ .location = 3 },
});

// Vertex output
const f_texture_index = @extern(*addrspace(.output) u32, .{
    .name = "f_texture_index",
    .decoration = .{ .flat = 0 },
});

const f_texture_coords = @extern(*addrspace(.output) @Vector(2, f32), .{
    .name = "f_texture_coords",
    .decoration = .{ .location = 1 },
});

const f_fg_color = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "f_fg_color",
    .decoration = .{ .location = 2 },
});

const f_bg_color = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "f_bg_color",
    .decoration = .{ .location = 3 },
});

export fn main() callconv(.spirv_vertex) void {
    const vertex_index = std.spirv.vertex_index;

    const quad_position = @Vector(2, f32){
        @floatFromInt((@as(u32, 14) >> @truncate(vertex_index)) & 1),
        @floatFromInt((@as(u32, 28) >> @truncate(vertex_index)) & 1),
    };

    const lo = p_glyph_entry.*[0];
    const hi = p_glyph_entry.*[1];

    const atlas_id = bitfieldExtractFromU32(lo, 0, 8, .unsigned);

    const glyph_pos = @Vector(2, f32){
        @floatFromInt(bitfieldExtractFromU32(lo, 8, 12, .unsigned)),
        @floatFromInt(bitfieldExtractFromU32(lo, 20, 12, .unsigned)),
    };

    const glyph_size = @Vector(2, f32){
        @floatFromInt(bitfieldExtractFromU32(hi, 0, 8, .unsigned)),
        @floatFromInt(bitfieldExtractFromU32(hi, 8, 8, .unsigned)),
    };

    const glyph_bearing = @Vector(2, f32){
        @floatFromInt(bitfieldExtractFromU32(hi, 16, 8, .signed)),
        @floatFromInt(bitfieldExtractFromU32(hi, 24, 8, .signed)),
    };

    const row = bitfieldExtractFromU32(p_postion.*, 0, 16, .unsigned);
    const col = bitfieldExtractFromU32(p_postion.*, 16, 16, .unsigned);

    const cell_origin = @Vector(2, f32){ @floatFromInt(col), @floatFromInt(row) } * ubo.cell_size;
    const glyph_offset = cell_origin + @Vector(2, f32){ 0.0, ubo.baseline } + glyph_bearing;
    const vertex_position = glyph_offset + quad_position * glyph_size;

    const clip_position = vertex_position * ubo.screen_to_clip_scale + ubo.screen_to_clip_offset;

    std.spirv.position_out.* = .{ clip_position[0], clip_position[1], 0.0, 1.0 };

    f_texture_index.* = atlas_id;
    f_texture_coords.* = (glyph_pos + quad_position * glyph_size) * ubo.inv_atlas_size;
    f_fg_color.* = fg_color.*;
    f_bg_color.* = bg_color.*;
}
