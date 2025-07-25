#version 450 core

layout(location = 0) in vec2 TexCoords;
layout(location = 1) in vec4 v_fg_color;
layout(location = 2) in vec4 v_bg_color;

layout(location = 0) out vec4 FragColor;

layout(binding = 0) uniform sampler2D atlas_texture;

void main() {
    float alpha = texture(atlas_texture, TexCoords).r;
    FragColor = mix(v_bg_color, v_fg_color, alpha);
}
