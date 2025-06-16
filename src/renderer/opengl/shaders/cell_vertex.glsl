#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in ivec2 cell_coord;

uniform vec2 glyph_uv_size; 
uniform vec2 cell_pixel_size;
uniform vec2 screen_size;

out vec2 v_uv;

void main() {
    vec2 pixel_pos = cell_coord.yx * cell_pixel_size;
    vec2 vertex_pixel_pos = pixel_pos + a_pos * cell_pixel_size;

    vec2 ndc_pos = vertex_pixel_pos / screen_size * 2.0f - 1.0f;
    ndc_pos *= -1.0f;

    gl_Position = vec4(ndc_pos, 0.0f, 0.1f);

    vec2 atlas_uv_offset = cell_coord * glyph_uv_size;
    v_uv = atlas_uv_offset + a_uv * glyph_uv_size
}
