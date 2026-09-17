#version 450 core

#extension GL_EXT_nonuniform_qualifier: enable

// -------------------------------------------------
// input
// -------------------------------------------------
layout(location = 0) flat in uint texture_index;
layout(location = 1) in vec2 texture_coords;
layout(location = 2) in vec4 fg_color;
layout(location = 3) in vec4 bg_color;

// -------------------------------------------------
// output
// -------------------------------------------------
layout(location = 0) out vec4 frag_color;

// -------------------------------------------------
// uniform
// -------------------------------------------------
layout(set = 1, binding = 0) uniform sampler2D textures[];

void main() {
    float alpha = texture(textures[texture_index], texture_coords).r;
    frag_color = mix(bg_color, fg_color, alpha);
}
