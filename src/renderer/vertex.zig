pub const Vertex = packed struct {
    quad_vertex: math.Vec4(f32), // postion, uv
};

pub const PackedPostion = packed struct(u32) { row: u16, col: u16 };

pub const Instance = packed struct {
    packed_pos: PackedPostion,
    glyph_index: u32,
    style_index: u32,
};

pub const GlyphMetrics = packed struct {
    coord_start: math.Vec2(u32),
    coord_end: math.Vec2(u32),
    bearing: math.Vec2(i32),
};

pub const GlyphStyle = packed struct {
    fg_color: math.Vec4(f32),
    bg_color: math.Vec4(f32),
};

pub const Uniforms = packed struct {
    cell_height: f32,
    cell_width: f32,
    screen_height: f32,
    screen_width: f32,
    atlas_cols: f32,
    atlas_rows: f32,
    atlas_width: f32,
    atlas_height: f32,
    descender: f32,
};

pub const TextUniform = packed struct {
    screen_to_clip_scale: math.Vec2(f32),
    screen_to_clip_offset: math.Vec2(f32),
    inv_atlas_size: math.Vec2(f32), // 1 / atlas_size
    cell_size: math.Vec2(f32),
    baseline: f32,
};

const math = @import("math");
const color = @import("color");
