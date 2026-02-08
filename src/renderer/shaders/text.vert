#version 450 core
#extension GL_GOOGLE_include_directive : require

#include "data.glsl"

// -------------------------------------------------
// input
// -------------------------------------------------

// `p_` prefex means that the input variable is bit packed data
layout(location = 0) in uint p_postion;
layout(location = 1) in uvec2 p_glyph_entry;
layout(location = 2) in vec4 fg_color;
layout(location = 3) in vec4 bg_color;

// -------------------------------------------------
// output
// -------------------------------------------------
layout(location = 0) out uint f_texture_index;
layout(location = 1) out vec2 f_texture_coords;
layout(location = 2) out vec4 f_fg_color;
layout(location = 3) out vec4 f_bg_color;

// -------------------------------------------------
// uniform
// -------------------------------------------------
layout(set = 0, binding = 0) uniform TextUniform {
  vec2 screen_to_clip_scale;
  vec2 screen_to_clip_offset;
  vec2 inv_atlas_size;
  vec2 cell_size;
  float baseline;
} ubo;

void main() {
  vec2 quad_position;
  quad_position.x = float(gl_VertexIndex & 1);
  quad_position.y = float((gl_VertexIndex >> 1u) & 1u);

  GlyphAtlasEntry glyph = unpackGlyphEntry(p_glyph_entry);

  uint row = p_postion & 0xFFFF;
  uint col = (p_postion >> 16) & 0xFFFF;

  vec2 cell_origin = vec2(col, row) * ubo.cell_size;

  vec2 glyph_offset = cell_origin + vec2(0.0, ubo.baseline) + glyph.bearing * vec2(1.0, -1.0);
  vec2 vertex_position = glyph_offset + quad_position * glyph.size;

  gl_Position = vec4(vertex_position * ubo.screen_to_clip_scale + ubo.screen_to_clip_offset, 0.0, 1.0);

  f_texture_coords = (glyph.pos + quad_position * glyph.size) * ubo.inv_atlas_size;

  f_texture_index = glyph.atlas_id;
  f_fg_color = fg_color;
  f_bg_color = bg_color;
}
