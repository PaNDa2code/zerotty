const OpenGLRenderer = @This();

threadlocal var gl_proc: *gl.ProcTable = undefined;

allocator: Allocator,
context: OpenGLContext,
shader_program: gl.uint,
window_height: u32,
window_width: u32,
atlas_texture: gl.uint,

quad_vao: gl.uint,
quad_vbo: gl.uint,
quad_ebo: gl.uint,

vao: gl.uint,
vbo: gl.uint,

atlas: Atlas,
grid: Grid,

pub const InitError = shader_utils.CreateShaderProgramError ||
    Allocator.Error || CreateOpenGLContextError || Atlas.CreateError;

pub fn init(window: *Window, allocator: Allocator) InitError!OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.allocator = allocator;
    self.context = try OpenGLContext.createOpenGLContext(window);

    gl_proc = try @import("proc_table.zig").createProcTable(allocator);
    gl.makeProcTableCurrent(gl_proc);

    self.window_height = window.height;
    self.window_width = window.width;

    self.atlas = try self.createAtlasTexture(allocator);
    self.grid = try Grid.create(allocator, .{
        .screen_height = self.window_height,
        .screen_width = self.window_width,
        .cell_height = self.atlas.cell_height,
        .cell_width = self.atlas.cell_width,
    });

    // load_proc_once.call();

    if (builtin.mode == .Debug) {
        gl.Enable(gl.DEBUG_OUTPUT);
        gl.DebugMessageCallback(@import("debug.zig").openglDebugCallback, null);
    }

    self.shader_program = try shader_utils.createShaderProgram(vertex_shader_spv, fragment_shader_spv);

    self.setupBuffers();

    return self;
}

fn setupBuffers(self: *OpenGLRenderer) void {
    // ========== Vertex Array Object ========== //
    var vao: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao));
    gl.BindVertexArray(vao);
    self.vao = vao;

    // ========== Vertex Buffer Object (Quad) ========== //
    const full_quad = [_]Vec4(f32){
        .{ .x = -0.5, .y = -0.5, .z = 0.0, .w = 0.0 }, // Bottom-left
        .{ .x = 0.5, .y = -0.5, .z = 1.0, .w = 0.0 }, // Bottom-right
        .{ .x = 0.5, .y = 0.5, .z = 1.0, .w = 1.0 }, // Top-right
        .{ .x = -0.5, .y = 0.5, .z = 0.0, .w = 1.0 }, // Top-left
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
    // ========== Vertex Buffer Object (Instance) ========== //
    var instance_vbo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&instance_vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, instance_vbo);

    const size: usize = self.grid.data.len * @sizeOf(Cell);

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
    gl.VertexAttribPointer(4, 4, gl.FLOAT, gl.FALSE, @sizeOf(Cell), @offsetOf(Cell, "fg_color"));
    gl.VertexAttribDivisor(4, 1); // fg_color

    gl.EnableVertexAttribArray(5);
    gl.VertexAttribPointer(5, 4, gl.FLOAT, gl.FALSE, @sizeOf(Cell), @offsetOf(Cell, "bg_color"));
    gl.VertexAttribDivisor(5, 1); // bg_color

    self.vbo = instance_vbo;
    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
}

fn setUniforms(self: *OpenGLRenderer) void {
    gl.Uniform1f(gl.GetUniformLocation(self.shader_program, "cell_height"), @floatFromInt(self.atlas.cell_height));
    gl.Uniform1f(gl.GetUniformLocation(self.shader_program, "cell_width"), @floatFromInt(self.atlas.cell_width));
    gl.Uniform1f(gl.GetUniformLocation(self.shader_program, "screen_height"), @floatFromInt(self.window_height));
    gl.Uniform1f(gl.GetUniformLocation(self.shader_program, "screen_width"), @floatFromInt(self.window_width));

    gl.Uniform1f(gl.GetUniformLocation(self.shader_program, "atlas_cols"), @floatFromInt(self.atlas.cols));
    gl.Uniform1f(gl.GetUniformLocation(self.shader_program, "atlas_rows"), @floatFromInt(self.atlas.rows));

    gl.Uniform1i(gl.GetUniformLocation(self.shader_program, "atlas_texture"), 0);
}

fn createAtlasTexture(self: *OpenGLRenderer, allocator: Allocator) Atlas.CreateError!Atlas {
    const atlas = try Atlas.create(allocator, 30, 20, 0, 128);

    var atlas_texture: gl.uint = 0;
    gl.GenTextures(1, @ptrCast(&atlas_texture));
    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_2D, atlas_texture);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        gl.R8,
        @intCast(atlas.width),
        @intCast(atlas.height),
        0,
        gl.RED,
        gl.UNSIGNED_BYTE,
        atlas.buffer.ptr,
    );

    self.atlas_texture = atlas_texture;

    return atlas;
}

pub fn deinit(self: *OpenGLRenderer) void {
    gl.makeProcTableCurrent(null);
    self.allocator.destroy(gl_proc);
    self.context.destory();
    self.atlas.deinit(self.allocator);
    self.allocator.free(self.grid.data);
}

pub fn clearBuffer(self: *OpenGLRenderer, color: ColorRGBA) void {
    _ = self;
    gl.ClearColor(color.r, color.g, color.b, color.a);
    gl.Clear(gl.COLOR_BUFFER_BIT);
}

pub fn presentBuffer(self: *OpenGLRenderer) void {
    self.context.swapBuffers();
}

pub fn renaderText(self: *OpenGLRenderer, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    _ = color; // autofix
    _ = y; // autofix
    _ = x; // autofix
    _ = buffer; // autofix

    gl.BindVertexArray(self.vao);
    defer gl.BindVertexArray(0);

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.quad_ebo);
    defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

    gl.BindTexture(gl.TEXTURE_2D, self.atlas_texture);
    defer gl.BindTexture(gl.TEXTURE_2D, 0);

    gl.UseProgram(self.shader_program);
    defer gl.UseProgram(0);

    self.setUniforms();

    gl.BufferData(
        gl.ARRAY_BUFFER,
        @intCast(@sizeOf(Cell) * self.grid.data.len),
        self.grid.data.ptr,
        gl.DYNAMIC_DRAW,
    );

    gl.DrawElementsInstanced(
        gl.TRIANGLES,
        6,
        gl.UNSIGNED_INT,
        null,
        @intCast(self.grid.data.len),
    );
}

pub fn resize(self: *OpenGLRenderer, width: u32, height: u32) !void {
    self.window_width = width;
    self.window_height = height;
    try self.grid.resize(self.allocator, .{
        .screen_height = height,
        .screen_width = width,
        .cell_height = self.atlas.cell_height,
        .cell_width = self.atlas.cell_width,
    });
    gl.Viewport(0, 0, @intCast(width), @intCast(height));
}

const OpenGLContext = switch (builtin.os.tag) {
    .windows => @import("WGLContext.zig"),
    .linux => @import("GLXContext.zig"),
    else => void,
};

const CreateOpenGLContextError = OpenGLContext.CreateOpenGLContextError;

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const gl = @import("gl");

const shader_utils = @import("shader_utils.zig");
const font = @import("../../font/root.zig");
const Window = @import("../../window/root.zig").Window;
const Atlas = font.Atlas;
const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
const math = @import("../math.zig");
const Vec4 = math.Vec4;
const Grid = @import("../Grid.zig");
const Cell = Grid.Cell;

const assets = @import("assets");
const shaders = assets.shaders;
const vertex_shader_spv = shaders.cell_vert;
const fragment_shader_spv = shaders.cell_frag;
