#ifndef DATA_GLSL
#define DATA_GLSL

struct TextUniform {
  vec2 screen_to_clip_scale;
  vec2 screen_to_clip_offset;
  vec2 inv_atlas_size;
  vec2 cell_size;
  float baseline;
};

struct GlyphAtlasEntry {
  uint atlas_id;
  uvec2 pos;
  uvec2 size;
  ivec2 bearing;
};

GlyphAtlasEntry unpackGlyphEntry(uvec2 packed) {
  uint lo = packed.x;
  uint hi = packed.y;

  GlyphAtlasEntry entry;

  entry.atlas_id = lo & 0xFFu;
  entry.pos.x = (lo >> 8u) & 0xFFFu;
  entry.pos.y = (lo >> 20u) & 0xFFFu;

  entry.size.x = hi & 0xFFu;
  entry.size.y = (hi >> 8u) & 0xFFu;

  entry.bearing.x = int((hi >> 16u) & 0xFFu) << 24u >> 24u;
  entry.bearing.y = int((hi >> 24u) & 0xFFu) << 24u >> 24u;

  return g;
}

#endif
