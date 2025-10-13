#version 450 core

// Vertex inputs

// layout(location = 0) in vec4 quad_vertex; // xy = position, zw = UV
layout(location = 1) in uint row;
layout(location = 2) in uint col;
layout(location = 3) in uint character;
layout(location = 4) in vec4 fg_color;
layout(location = 5) in vec4 bg_color;

layout(location = 6) in uvec2 coord_start;
layout(location = 7) in uvec2 coord_end;
layout(location = 8) in ivec2 bearing;

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

// Outputs
layout(location = 0) out vec2 TexCoords;
layout(location = 1) out vec4 v_fg_color;
layout(location = 2) out vec4 v_bg_color;

void main() {
    // bitmask trick to generate a full quad vertices.
    // no noticeable preformace gain, but it was fun
    // to come up with
    vec2 position;
#ifdef VULKAN
    // 14 = 0b1110, 28 = 0b11100
    position.x = float((14 >> gl_VertexIndex) & 1);
    position.y = float((28 >> gl_VertexIndex) & 1);
#else
    // 6 = 0b0110, 12 = 0b1100
    position.x = float((6 >> gl_VertexID) & 1);
    position.y = float((12 >> gl_VertexID) & 1);
#endif

    vec2 atlas_size = vec2(ubo.atlas_width, ubo.atlas_height);
    vec2 cell_size = vec2(ubo.cell_width, ubo.cell_height);
    vec2 screen_size = vec2(ubo.screen_width, ubo.screen_height);

    // Calculate position
    vec2 cell_origin = vec2(col, row) * cell_size;

    float baseline = ubo.cell_height + ubo.descender;
    vec2 glyph_origin = cell_origin + vec2(0.0, baseline);
    vec2 glyph_bearing = vec2(bearing.x, -bearing.y);

    vec2 glyph_size = vec2(coord_end - coord_start);

    vec2 vertex_pos = glyph_origin + glyph_bearing + position * glyph_size;

    // Convert to clip space
    vec2 normalized = vertex_pos / screen_size;
    vec2 clip_pos = normalized * 2.0 - 1.0;

#ifndef VULKAN
    clip_pos.y = -clip_pos.y; // Flip Y for OpenGL
#endif

    gl_Position = vec4(clip_pos, 0.0, 1.0);

    vec2 uv_min = vec2(coord_start) / atlas_size;
    vec2 uv_max = vec2(coord_end) / atlas_size;
    vec2 uv_range = uv_max - uv_min;

    TexCoords = uv_min + position * uv_range;

    // Pass colors
    v_fg_color = fg_color;
    v_bg_color = bg_color;
}
