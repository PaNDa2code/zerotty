const OpenGLRenderer = @This();

// OpenGL renderer

threadlocal var gl_proc: gl.ProcTable = undefined;
threadlocal var gl_lib: DynamicLibrary = undefined;
threadlocal var gl_proc_is_loaded: bool = false;

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
cell_program: CellProgram,
raster: @import("Rasterizer.zig"),

fn getProc(name: [*:0]const u8) ?*const anyopaque {
    var p: ?*const anyopaque = null;

    p = OpenGLContext.glGetProcAddress(name);

    // https://www.khronos.org/opengl/wiki/Load_OpenGL_Functions
    if (p == null or
        builtin.os.tag == .windows and
            (p == @as(?*const anyopaque, @ptrFromInt(1)) or
                p == @as(?*const anyopaque, @ptrFromInt(2)) or
                p == @as(?*const anyopaque, @ptrFromInt(3)) or
                p == @as(?*const anyopaque, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))))))
    {
        p = gl_lib.getProcAddress(name);
    }

    return p;
}

fn getProcTableOnce() void {
    const opengl_lib_name = switch (@import("builtin").os.tag) {
        .windows => "opengl32.dll",
        .linux => "libGL.so",
        else => {},
    };

    gl_lib = DynamicLibrary.init(opengl_lib_name) catch @panic("can't load OpenGL library");

    if (!gl_proc.init(getProc))
        @panic("failed to load opengl proc table");

    gl.makeProcTableCurrent(&gl_proc);
}

const vertex_shader_source = @embedFile("shaders/vertex.glsl");
const fragment_shader_source = @embedFile("shaders/fragment.glsl");

const OpenGLRendererInitaliztionError = error{} || shader_utils.CreateShaderProgramError || Allocator.Error;

pub fn init(window: *Window, allocator: Allocator) !OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.allocator = allocator;
    self.context = try OpenGLContext.createOpenGLContext(window);

    if (!gl_proc_is_loaded)
        getProcTableOnce();

    self.window_height = window.height;
    self.window_width = window.width;

    self.atlas = try self.createAtlasTexture(allocator);
    self.cell_program = try CellProgram.create(allocator, self.window_height, self.window_width, self.atlas.cell_width);

    // load_proc_once.call();

    if (builtin.mode == .Debug) {
        gl.Enable(gl.DEBUG_OUTPUT);
        gl.DebugMessageCallback(@import("debug.zig").openglDebugCallback, null);
    }

    self.shader_program = try shader_utils.createShaderProgram(vertex_shader_source, fragment_shader_source);

    self.setupVAO();

    return self;
}

fn setupVAO(self: *OpenGLRenderer) void {
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

    const size: usize = self.cell_program.data.len * @sizeOf(Cell);

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

fn createAtlasTexture(self: *OpenGLRenderer, allocator: Allocator) !Atlas {
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
    gl_lib.deinit();
    self.context.destory();
    self.atlas.deinit(self.allocator);
    self.allocator.free(self.cell_program.data);
}

pub fn clearBuffer(self: *OpenGLRenderer, color: ColorRGBA) void {
    _ = self;
    gl_proc.ClearColor(color.r, color.g, color.b, color.a);
    gl_proc.Clear(gl.COLOR_BUFFER_BIT);
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
        @intCast(@sizeOf(Cell) * self.cell_program.data.len),
        self.cell_program.data.ptr,
        gl.DYNAMIC_DRAW,
    );

    gl.DrawElementsInstanced(
        gl.TRIANGLES,
        6,
        gl.UNSIGNED_INT,
        null,
        @intCast(self.cell_program.data.len),
    );
}

pub fn resize(self: *OpenGLRenderer, width: u32, height: u32) void {
    self.window_width = width;
    self.window_height = height;
}

const OpenGLContext = switch (builtin.os.tag) {
    .windows => @import("WGLContext.zig"),
    .linux => @import("GLXContext.zig"),
    else => void,
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const freetype = @import("freetype");
const gl = @import("gl");

const shader_utils = @import("shader_utils.zig");
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const Window = @import("../../window.zig").Window;
const Atlas = @import("../Atlas.zig");
const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
const math = @import("../math.zig");
const Vec4 = math.Vec4;
const CellProgram = @import("CellProgram.zig");
const Cell = CellProgram.Cell;
