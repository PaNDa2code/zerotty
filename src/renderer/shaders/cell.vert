#version 450 core

// Vertex inputs
layout(location = 0) in vec4 quad_vertex; // xy = position, zw = UV
layout(location = 1) in uint row;
layout(location = 2) in uint col;
layout(location = 3) in uint character;
layout(location = 4) in vec4 fg_color;
layout(location = 5) in vec4 bg_color;

layout(location = 6) in uvec2 coord_start;
layout(location = 7) in uvec2 coord_end;
layout(location = 8) in uvec2 bearing;

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
} ubo;

// Outputs
layout(location = 0) out vec2 TexCoords;
layout(location = 1) out vec4 v_fg_color;
layout(location = 2) out vec4 v_bg_color;

void main() {
    vec2 cell_size = vec2(ubo.cell_width, ubo.cell_height);
    vec2 screen_size = vec2(ubo.screen_width, ubo.screen_height);

    // Calculate position
    vec2 grid_pos = vec2(float(col), float(row)) * cell_size;
    vec2 vertex_pos = grid_pos + quad_vertex.xy * cell_size;

    // Convert to clip space
    vec2 normalized = vertex_pos / screen_size;
    vec2 clip_pos = normalized * 2.0 - 1.0;
    clip_pos.y = -clip_pos.y; // Flip Y for OpenGL

    gl_Position = vec4(clip_pos, 0.0, 1.0);

    vec2 uv_min = vec2(coord_start) / vec2(ubo.atlas_width, ubo.atlas_height);
    vec2 uv_max = vec2(coord_end) / vec2(ubo.atlas_width, ubo.atlas_height);
    vec2 uv_range = uv_max - uv_min;

    TexCoords = uv_min + quad_vertex.zw * uv_range;

    // Pass colors
    v_fg_color = fg_color;
    v_bg_color = bg_color;
}
