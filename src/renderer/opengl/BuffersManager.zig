const BuffersManager = @This();

vao: gl.uint,
quad_vbo: gl.uint,
quad_ebo: gl.uint,
instance_vbo: gl.uint,
ubo: gl.uint,

pub const UniformsBlock = packed struct {
    cell_height: f32,
    cell_width: f32,
    screen_height: f32,
    screen_width: f32,
    atlas_cols: f32,
    atlas_rows: f32,
    atlas_width: f32,
    atlas_height: f32,
    descender: f32,
};

pub fn init(instance_len: usize) BuffersManager {
    var self: BuffersManager = undefined;
    self.initAndBindVAO();
    self.initQuadBuffers();
    self.initInstanceBuffer(instance_len);
    self.initUBO();
    return self;
}

pub fn bindVAO(self: *const BuffersManager) void {
    gl.BindVertexArray(self.vao);
}
pub fn unbindVAO(_: *const BuffersManager) void {
    gl.BindVertexArray(0);
}

pub fn bindQuadEBO(self: *const BuffersManager) void {
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.quad_ebo);
}

pub fn bindInstaceVBO(self: *const BuffersManager) void {
    gl.BindBuffer(gl.ARRAY_BUFFER, self.instance_vbo);
}

fn initAndBindVAO(self: *BuffersManager) void {
    // ========== Vertex Array Object ========== //
    var vao: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao));
    gl.BindVertexArray(vao);
    self.vao = vao;
}

fn initQuadBuffers(self: *BuffersManager) void {
    // ========== Vertex Buffer Object (Quad) ========== //
    const full_quad = [_]Vec4(f32){
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 }, // Bottom-left
        .{ .x = 1.0, .y = 0.0, .z = 1.0, .w = 0.0 }, // Bottom-right
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // Top-right
        .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }, // Top-left
    };

    const full_quad_indices = [_]u32{
        0, 1, 2, // First triangle
        2, 3, 0, // Second triangle
    };

    var quad_ebo: u32 = undefined;
    gl.GenBuffers(1, @ptrCast(&quad_ebo));
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad_ebo);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * full_quad_indices.len, &full_quad_indices, gl.STATIC_DRAW);
    self.quad_ebo = quad_ebo;
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    var quad_vbo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&quad_vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, quad_vbo);

    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(Vec4(f32)) * full_quad.len, &full_quad, gl.STATIC_DRAW);

    gl.EnableVertexAttribArray(0);
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vec4(f32)), 0);
    gl.VertexAttribDivisor(0, 0); // quad_vertex
    self.quad_vbo = quad_vbo;

    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
}

fn initInstanceBuffer(self: *BuffersManager, instance_len: usize) void {
    // ========== Vertex Buffer Object (Instance) ========== //
    var instance_vbo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&instance_vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, instance_vbo);

    const size: usize = instance_len * (@sizeOf(Cell) + @sizeOf(Atlas.GlyphInfo));

    gl.BufferData(gl.ARRAY_BUFFER, @bitCast(size), null, gl.DYNAMIC_DRAW);

    gl.EnableVertexAttribArray(1);
    gl.VertexAttribIPointer(1, 1, gl.UNSIGNED_INT, @sizeOf(Cell), @offsetOf(Cell, "row"));
    gl.VertexAttribDivisor(1, 1); // row

    gl.EnableVertexAttribArray(2);
    gl.VertexAttribIPointer(2, 1, gl.UNSIGNED_INT, @sizeOf(Cell), @offsetOf(Cell, "col"));
    gl.VertexAttribDivisor(2, 1); // col

    gl.EnableVertexAttribArray(3);
    gl.VertexAttribIPointer(3, 1, gl.UNSIGNED_INT, @sizeOf(Cell), @offsetOf(Cell, "char"));
    gl.VertexAttribDivisor(3, 1); // char

    gl.EnableVertexAttribArray(4);
    gl.VertexAttribPointer(4, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Cell), @offsetOf(Cell, "fg_color"));
    gl.VertexAttribDivisor(4, 1); // fg_color

    gl.EnableVertexAttribArray(5);
    gl.VertexAttribPointer(5, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Cell), @offsetOf(Cell, "bg_color"));
    gl.VertexAttribDivisor(5, 1); // bg_color

    gl.EnableVertexAttribArray(6);
    gl.VertexAttribIPointer(6, 2, gl.UNSIGNED_INT, @sizeOf(Cell), @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "coord_start"));
    gl.VertexAttribDivisor(6, 1); // coord_start

    gl.EnableVertexAttribArray(7);
    gl.VertexAttribIPointer(7, 2, gl.UNSIGNED_INT, @sizeOf(Cell), @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "coord_end"));
    gl.VertexAttribDivisor(7, 1); // coord_end

    gl.EnableVertexAttribArray(8);
    gl.VertexAttribIPointer(8, 2, gl.INT, @sizeOf(Cell), @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "bearing"));
    gl.VertexAttribDivisor(8, 1); // bearing

    self.instance_vbo = instance_vbo;
    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
}

fn initUBO(self: *BuffersManager) void {
    var ubo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&ubo));
    gl.BindBuffer(gl.UNIFORM_BUFFER, ubo);
    gl.BufferData(gl.UNIFORM_BUFFER, @sizeOf(UniformsBlock), null, gl.DYNAMIC_DRAW);
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0);
    self.ubo = ubo;
}

const gl = @import("gl");
const math = @import("../math.zig");
const font = @import("../../font/root.zig");
const Vec2 = math.Vec2;
const Vec4 = math.Vec4;
const Grid = @import("../Grid.zig");
const Cell = Grid.Cell;
const Atlas = font.Atlas;
