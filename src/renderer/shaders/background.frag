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
  float baseline;
  float grid_cols;
  float grid_rows;
} ubo;

layout(set = 0, binding = 1) uniform sampler2D u_cell_colors;

void main() {
  ivec2 cell = ivec2(gl_FragCoord.xy / ubo.cell_size);

  // Fragments outside the grid (partial cells at the bottom/right edge)
  // fall back to the clear color, which matches the default background.
  if (cell.x >= int(ubo.grid_cols) || cell.y >= int(ubo.grid_rows)) {
    frag_color = vec4(0.0);
    return;
  }

  vec2 texel = (vec2(cell) + 0.5) / vec2(ubo.grid_cols, ubo.grid_rows);
  frag_color = texture(u_cell_colors, texel);
}
