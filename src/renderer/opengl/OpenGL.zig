const OpenGLRenderer = @This();

threadlocal var gl_proc: *gl.ProcTable = undefined;

allocator: Allocator,
context: OpenGLContext,
window_height: u32,
window_width: u32,
atlas_texture: gl.uint,

bufs: BuffersManager,
shader_program: ShaderProgram,

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
        .rows = self.window_height / self.atlas.cell_height,
        .cols = self.window_width / self.atlas.cell_width,
    });

    // load_proc_once.call();

    if (builtin.mode == .Debug) {
        gl.Enable(gl.DEBUG_OUTPUT);
        gl.DebugMessageCallback(@import("debug.zig").openglDebugCallback, null);
    }

    self.shader_program = ShaderProgram.init();
    try self.shader_program.attachShaderSPIRV(&vertex_shader_spv, .Vertex);
    try self.shader_program.attachShaderSPIRV(&fragment_shader_spv, .Fragment);
    self.shader_program.linkProgram();

    self.bufs = BuffersManager.init(self.grid.data().len);

    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    return self;
}

const UniformsBlock = packed struct {
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

fn setUniforms(self: *OpenGLRenderer) void {
    const data = UniformsBlock{
        .cell_height = @floatFromInt(self.atlas.cell_height),
        .cell_width = @floatFromInt(self.atlas.cell_width),
        .screen_height = @floatFromInt(self.window_height),
        .screen_width = @floatFromInt(self.window_width),
        .atlas_cols = @floatFromInt(self.atlas.cols),
        .atlas_rows = @floatFromInt(self.atlas.rows),
        .atlas_height = @floatFromInt(self.atlas.height),
        .atlas_width = @floatFromInt(self.atlas.width),
        .descender = @floatFromInt(self.atlas.descender),
    };
    gl.BindBuffer(gl.UNIFORM_BUFFER, self.bufs.ubo);
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, @sizeOf(UniformsBlock), &data);
    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, self.bufs.ubo);
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0);
}

fn createAtlasTexture(self: *OpenGLRenderer, allocator: Allocator) Atlas.CreateError!Atlas {
    const atlas = try Atlas.create(allocator, 30, 20, 0, 128);

    var atlas_texture: gl.uint = 0;
    gl.GenTextures(1, @ptrCast(&atlas_texture));
    gl.ActiveTexture(gl.TEXTURE1);
    gl.BindTexture(gl.TEXTURE_2D, atlas_texture);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
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
    self.grid.free();
}

pub fn clearBuffer(self: *OpenGLRenderer, color: ColorRGBA32) void {
    _ = self;
    gl.ClearColor(color.r, color.g, color.b, color.a);
    gl.Clear(gl.COLOR_BUFFER_BIT);
}

pub fn presentBuffer(self: *OpenGLRenderer) void {
    self.context.swapBuffers();
}

pub fn renaderGrid(self: *OpenGLRenderer) void {
    self.bufs.bindVAO();
    defer gl.BindVertexArray(0);

    self.bufs.bindQuadEBO();
    defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    self.bufs.bindInstaceVBO();
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

    gl.BindTexture(gl.TEXTURE_2D, self.atlas_texture);
    defer gl.BindTexture(gl.TEXTURE_2D, 0);

    self.shader_program.useProgram();
    defer gl.UseProgram(0);

    self.setUniforms();

    gl.BufferData(
        gl.ARRAY_BUFFER,
        @intCast(@sizeOf(Cell) * self.grid.data().len),
        self.grid.data().ptr,
        gl.DYNAMIC_DRAW,
    );

    gl.DrawElementsInstanced(
        gl.TRIANGLES,
        6,
        gl.UNSIGNED_INT,
        0,
        @intCast(self.grid.data().len),
    );
}

pub fn resize(self: *OpenGLRenderer, width: u32, height: u32) !void {
    self.window_width = width;
    self.window_height = height;
    try self.grid.resize(self.allocator, .{
        .rows = height / self.atlas.cell_height,
        .cols = width / self.atlas.cell_width,
    });
    gl.Viewport(0, 0, @intCast(width), @intCast(height));
}

pub fn setCell(
    self: *OpenGLRenderer,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    try self.grid.set(.{
        .row = row,
        .col = col,
        .char = char_code,
        .fg_color = fg_color orelse .White,
        .bg_color = bg_color orelse .Black,
        .glyph_info = self.atlas.glyph_lookup_map.get(char_code) orelse self.atlas.glyph_lookup_map.get(' ').?,
    });
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
const ColorRGBA32 = common.ColorRGBAf32;
const ColorRGBAu8 = common.ColorRGBAu8;
const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec4 = math.Vec4;
const Grid = @import("../Grid.zig");
const Cell = Grid.Cell;
const BuffersManager = @import("BuffersManager.zig");
const ShaderProgram = @import("Shader.zig");

const assets = @import("assets");
const shaders = assets.shaders;
const vertex_shader_spv = shaders.cell_vert;
const fragment_shader_spv = shaders.cell_frag;
