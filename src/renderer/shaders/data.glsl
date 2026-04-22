#ifndef DATA_GLSL
#define DATA_GLSL

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

#ifndef NO_BIT_FIELD_EXTRACT
  entry.atlas_id = bitfieldExtract(lo, 0, 8);
  entry.pos.x = bitfieldExtract(lo, 8, 12);
  entry.pos.y = bitfieldExtract(lo, 20, 12);

  entry.size.x = bitfieldExtract(hi, 0, 8);
  entry.size.y = bitfieldExtract(hi, 8, 8);

  entry.bearing.x = bitfieldExtract(int(hi), 16, 8);
  entry.bearing.y = bitfieldExtract(int(hi), 24, 8);
#else
  entry.atlas_id = lo & 0xFFu;
  entry.pos.x = (lo >> 8u) & 0xFFFu;
  entry.pos.y = (lo >> 20u) & 0xFFFu;

  entry.size.x = hi & 0xFFu;
  entry.size.y = (hi >> 8u) & 0xFFu;

  entry.bearing.x = int((hi >> 16u) & 0xFFu) << 24u >> 24u;
  entry.bearing.y = int((hi >> 24u) & 0xFFu) << 24u >> 24u;
#endif

  return entry;
}

#endif
