// OpenGL renderer

threadlocal var gl_proc: gl.ProcTable = undefined;
threadlocal var gl_lib: DynamicLibrary = undefined;
threadlocal var gl_proc_is_loaded: bool = false;

context: OpenGLContext,
vertex_shader: gl.uint,
fragment_shader: gl.uint,
shader_program: gl.uint,
characters: [128]Character,
atlas: gl.uint,
window_height: u32,
window_width: u32,
VAO: gl.uint,
VBO: gl.uint,

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

pub fn init(window: *Window, allocator: Allocator) !OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.context = try OpenGLContext.createOpenGLContext(window);

    if (!gl_proc_is_loaded)
        getProcTableOnce();

    self.window_height = window.height;
    self.window_width = window.width;

    // load_proc_once.call();

    self.vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
    gl.ShaderSource(self.vertex_shader, 1, &.{@ptrCast(vertex_shader_source.ptr)}, null);

    self.fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    gl.ShaderSource(self.fragment_shader, 1, &.{@ptrCast(fragment_shader_source.ptr)}, null);

    gl.CompileShader(self.vertex_shader);
    gl.CompileShader(self.fragment_shader);

    self.shader_program = gl.CreateProgram();
    gl.AttachShader(self.shader_program, self.vertex_shader);
    gl.AttachShader(self.shader_program, self.fragment_shader);
    gl.LinkProgram(self.shader_program);

    gl.DeleteShader(self.vertex_shader);
    gl.DeleteShader(self.fragment_shader);

    self.atlas = try createAtlas(allocator, "res/fonts/FiraCodeNerdFontMono-Regular.ttf");

    var VAO: gl.uint = undefined;
    var VBO: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&VAO));
    gl.GenBuffers(1, @ptrCast(&VBO));
    gl.BindVertexArray(VAO);
    gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * 6 * 4, null, gl.DYNAMIC_DRAW);
    gl.EnableVertexAttribArray(0);
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0);

    self.VAO = VAO;
    self.VBO = VBO;

    return self;
}

pub fn deinit(self: *OpenGLRenderer) void {
    gl_lib.deinit();
    self.context.destory();
}

pub fn clearBuffer(self: *OpenGLRenderer, color: ColorRGBA) void {
    _ = self;
    gl_proc.ClearColor(color.r, color.g, color.b, color.a);
    gl_proc.Clear(gl.COLOR_BUFFER_BIT);
}

pub fn presentBuffer(self: *OpenGLRenderer) void {
    self.context.swapBuffers();
}

pub fn createAtlas(allocator: Allocator, font_path: []const u8) !gl.uint {
    const glyph_count = 128;
    const cell_size = 24;
    const atlas_columns = 16;
    const atlas_rows = (glyph_count + atlas_columns - 1) / atlas_columns;

    const atlas_width = cell_size * atlas_columns;
    const atlas_height = cell_size * atlas_rows;

    // Create the atlas texture in CPU before uploading it to the GPU
    const atlas_bytes = try allocator.alloc(u8, atlas_width * atlas_height);
    defer allocator.free(atlas_bytes);

    @memset(atlas_bytes, 0);

    const ft_lib = try freetype.Library.init(allocator);
    defer ft_lib.deinit();

    const ft_face = try ft_lib.face(font_path, cell_size);
    defer ft_face.deinit();

    for (0..glyph_count) |i| {
        const char_code: u8 = @intCast(i);
        var glyph = try ft_face.getGlyph(char_code);
        defer glyph.deinit();

        const bmp_glyph = try glyph.glyphBitmap();

        if (bmp_glyph.top <= 0 or bmp_glyph.bitmap.buffer == null) continue;

        const bmp = bmp_glyph.bitmap;
        const bmp_w = bmp.width;
        const bmp_h = bmp.rows;

        const col = i % atlas_columns;
        const row = i / atlas_columns;

        const cell_x = col * cell_size;
        const cell_y = row * cell_size;

        const dst_x = cell_x + (cell_size - bmp_w) / 2;
        const dst_y = cell_y + cell_size - @min(@as(usize, @intCast(bmp_glyph.top)), cell_size);

        const max_w = @min(bmp_w, atlas_width - dst_x);
        const max_h = if (dst_y >= atlas_height)
            0
        else
            @min(bmp_h, atlas_height - dst_y);

        std.log.debug("{0c} {0}", .{char_code});
        for (0..max_h) |y| {
            for (0..max_w) |x| {
                const src_idx = y * @as(usize, @intCast(bmp.pitch)) + x;
                const dst_idx = (dst_y + y) * atlas_width + (dst_x + x);
                atlas_bytes[dst_idx] = bmp.buffer.?[src_idx];
            }
        }
    }

    try saveAtlasAsPGM("atlas.PGM", atlas_bytes, atlas_width, atlas_height);

    // Upload to the GPU
    var tex: gl.uint = 0;
    gl.GenTextures(1, @ptrCast(&tex));
    gl.BindTexture(gl.TEXTURE_2D, tex);
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RED,
        atlas_width,
        atlas_height,
        0,
        gl.RED,
        gl.UNSIGNED_BYTE,
        atlas_bytes.ptr,
    );
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    return tex;
}

pub fn saveAtlasAsPGM(
    filename: []const u8,
    data: []const u8,
    width: usize,
    height: usize,
) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const writer = file.writer();

    // Write PGM header
    try writer.print("P5\n{} {}\n255\n", .{ width, height });

    // Write raw grayscale pixel data
    try writer.writeAll(data);
}

pub fn renaderText(self: *OpenGLRenderer, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    _ = color; // autofix
    _ = y; // autofix
    _ = x; // autofix
    _ = buffer; // autofix
    _ = self; // autofix
}

pub fn resize(self: *OpenGLRenderer, width: u32, height: u32) void {
    self.window_width = width;
    self.window_height = height;
}

const Character = packed struct {
    texture_id: u32,
    size: Vec2(i32),
    bearing: Vec2(i32),
    advance: u32,
};

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec4 = math.Vec4;

const OpenGLRenderer = @This();
const DynamicLibrary = @import("../../DynamicLibrary.zig");

const OpenGLContext = switch (builtin.os.tag) {
    .windows => @import("WGLContext.zig"),
    .linux => @import("GLXContext.zig"),
    else => void,
};

const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl");
const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
const Window = @import("../../window.zig").Window;
const freetype = @import("freetype");

const Allocator = std.mem.Allocator;
