#version 450 core

// Vertex inputs
layout(location = 0) in vec4 quad_vertex; // xy = position, zw = UV
layout(location = 1) in uint row;
layout(location = 2) in uint col;
layout(location = 3) in uint character;
layout(location = 4) in vec4 fg_color;
layout(location = 5) in vec4 bg_color;

// Uniforms
uniform float cell_height;
uniform float cell_width;
uniform float screen_height;
uniform float screen_width;
uniform float atlas_cols;
uniform float atlas_rows;

// Outputs
out vec2 TexCoords;
out vec4 FgColor;
out vec4 BgColor;

void main() {
    vec2 cell_size = vec2(cell_width, cell_height);
    vec2 screen_size = vec2(screen_width, screen_height);
    
    // Calculate position
    vec2 grid_pos = vec2(float(col), float(row)) * cell_size;
    vec2 vertex_pos = grid_pos + quad_vertex.xy * cell_size;
    
    // Convert to clip space
    vec2 normalized = vertex_pos / screen_size;
    vec2 clip_pos = normalized * 2.0 - 1.0;
    clip_pos.y = -clip_pos.y;  // Flip Y for OpenGL
    
    gl_Position = vec4(clip_pos, 0.0, 1.0);
    
    // Calculate texture coordinates
    float glyph_index = float(character);
    float glyph_x = mod(glyph_index, atlas_cols);
    float glyph_y = floor(glyph_index / atlas_cols);
    vec2 glyph_uv_size = vec2(1.0 / atlas_cols, 1.0 / atlas_rows);
    vec2 atlas_offset = vec2(glyph_x, glyph_y) * glyph_uv_size;
    
    TexCoords = atlas_offset + quad_vertex.zw * glyph_uv_size;
    
    // Pass colors
    FgColor = fg_color;
    BgColor = bg_color;
}
