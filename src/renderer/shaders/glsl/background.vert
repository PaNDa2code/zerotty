#version 450 core

void main() {
    // Single fullscreen triangle covering the entire viewport,
    // no vertex input / vertex buffer required.
    vec2 position = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    gl_Position = vec4(position * 2.0 - 1.0, 0.0, 1.0);
}
