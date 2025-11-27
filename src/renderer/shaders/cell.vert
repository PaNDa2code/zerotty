#version 450 core

#if !defined(VULKAN) && !defined(GL_SPIRV)
#error "This shader must be compiled for Vulkan or OpenGL"
#endif

struct GlyphMetrics {
    uvec2 coord_start;
    uvec2 coord_end;
    ivec2 bearing;
};

struct GlyphStyle {
    vec4 fg_color;
    vec4 bg_color;
};

// Vertex inputs
#ifdef GL_SPIRV
layout(location = 0) in vec4 quad_vertex; // xy = position, zw = UV
#endif

// packed_pos = (row << 16) | col
// Lower 16 bits = row, upper 16 bits = col
// Allows up to 65535 rows/cols, far beyond any real terminal size 
layout(location = 1) in uint packed_pos;

layout(location = 2) in uint glyph_index;
layout(location = 3) in uint style_index;

// Uniforms
layout(set = 0, binding = 0) uniform Uniforms {
    float cell_height;
    float cell_width;
    float screen_height;
    float screen_width;
    float atlas_cols;
    float atlas_rows;
    float atlas_height;
    float atlas_width;
    float descender;
} ubo;

// SSBOs
layout(std430, binding = 2) readonly buffer GlyphMetricsBuffer {
    GlyphMetrics glyph_metrics[];
};

layout(std430, binding = 3) readonly buffer GlyphStylesBuffer {
    GlyphStyle glyph_styles[];
};

// Outputs
layout(location = 0) out vec2 TexCoords;
layout(location = 1) out vec4 v_fg_color;
layout(location = 2) out vec4 v_bg_color;

void main() {
    vec2 position;

    #ifdef VULKAN
    // bitmask trick to generate a full quad vertices in flight.
    // no noticeable preformace gain, but it was fun to come up with
    // 14 = 0b1110, 28 = 0b11100
    position.x = float((14 >> gl_VertexIndex) & 1);
    position.y = float((28 >> gl_VertexIndex) & 1);
#elif GL_SPIRV
    position = quad_vertex.xy;
#endif

    vec2 atlas_size = vec2(ubo.atlas_width, ubo.atlas_height);
    vec2 cell_size = vec2(ubo.cell_width, ubo.cell_height);
    vec2 screen_size = vec2(ubo.screen_width, ubo.screen_height);

    uint row = packed_pos & 0xFFFF;
    uint col = (packed_pos >> 16) & 0xFFFF;

    // Calculate position
    vec2 cell_origin = vec2(col, row) * cell_size;

    float baseline = ubo.cell_height + ubo.descender;
    vec2 glyph_origin = cell_origin + vec2(0.0, baseline);
    vec2 glyph_bearing = vec2(glyph_metrics[glyph_index].bearing.x, -glyph_metrics[glyph_index].bearing.y);

    vec2 glyph_size = vec2(glyph_metrics[glyph_index].coord_end - glyph_metrics[glyph_index].coord_start);

    vec2 vertex_pos = glyph_origin + glyph_bearing + position * glyph_size;

    // Convert to clip space
    vec2 normalized = vertex_pos / screen_size;
    vec2 clip_pos = normalized * 2.0 - 1.0;

#ifdef GL_SPIRV
    clip_pos.y = -clip_pos.y; // Flip Y for OpenGL
#endif

    gl_Position = vec4(clip_pos, 0.0, 1.0);

    vec2 uv_min = vec2(glyph_metrics[glyph_index].coord_start) / atlas_size;
    vec2 uv_max = vec2(glyph_metrics[glyph_index].coord_end) / atlas_size;
    vec2 uv_range = uv_max - uv_min;

    TexCoords = uv_min + position * uv_range;

    // Pass colors
    v_fg_color = glyph_styles[style_index].fg_color;
    v_bg_color = glyph_styles[style_index].bg_color;
}
