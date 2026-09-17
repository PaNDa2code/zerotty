#version 450 core

// -------------------------------------------------
// output
// -------------------------------------------------
layout(location = 0) out vec4 frag_color;

// -------------------------------------------------
// uniform
// -------------------------------------------------
layout(set = 0, binding = 0) uniform TextUniform {
    vec2 screen_to_clip_scale;
    vec2 screen_to_clip_offset;
    vec2 inv_atlas_size; // 1 ÷ atlas_size
    vec2 cell_size;
    vec2 cell_size_inv;
    vec2 grid_size;
    vec4 bg_color;
    float baseline;
} ubo;

layout(set = 0, binding = 1) uniform sampler2D u_cell_colors;

void main() {
    ivec2 cell = ivec2(gl_FragCoord.xy * ubo.cell_size_inv);

    // Fragments outside the grid (partial cells at the bottom/right edge)
    // fall back to the clear color, which matches the default background.
    if (cell.x >= int(ubo.grid_size.x) || cell.y >= int(ubo.grid_size.y)) {
        frag_color = ubo.bg_color;
        return;
    }

    frag_color = texelFetch(u_cell_colors, cell, 0);
}
