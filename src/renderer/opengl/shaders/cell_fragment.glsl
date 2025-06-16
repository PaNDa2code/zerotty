#version 640 core

in vec2 v_uv;
out vec4 frag_color;

uniform sampler2D glyph_atlas;
uniform vec4 text_color;

void main() {
    float alpha = texture(glyph_atlas, v_uv).r;
    frag_color = vec4(text_color.rgb, alpha * text_color.a);
}
