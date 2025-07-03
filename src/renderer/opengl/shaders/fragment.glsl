#version 450 core

in vec2 TexCoords;

in vec4 v_fg_color;
in vec4 v_bg_color;

out vec4 FragColor;

uniform sampler2D atlas_texture;

void main() {
    float alpha = texture(atlas_texture, TexCoords).r;
    FragColor = mix(v_bg_color, v_fg_color, alpha);
}
