#version 450 core

in vec2 TexCoords;

in vec4 FgColor;
in vec4 BgColor;

out vec4 FragColor;

uniform sampler2D atlas_texture;

void main() {
    float alpha = texture(atlas_texture, TexCoords).r;
    FragColor = mix(BgColor, FgColor, alpha);
}
