#version 450 core

layout(location = 0) in vec2 TexCoords;
layout(location = 1) in vec4 v_fg_color;
layout(location = 2) in vec4 v_bg_color;

layout(location = 0) out vec4 FragColor;

layout(binding = 1) uniform sampler2D atlas_texture;

void main() {
  float glyph_mask = texture(atlas_texture, TexCoords).r;
  float alpha = glyph_mask * v_fg_color.a;

  vec3 rgb = mix(v_bg_color.rgb, v_fg_color.rgb, alpha);
  float out_alpha = mix(v_bg_color.a, v_fg_color.a, alpha);

  FragColor = vec4(rgb, out_alpha);
}
