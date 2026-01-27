//! Abstract renderer interface implemented by backends
const Renderer = @This();

backend: Backend,
fps: FPS,
cursor: Cursor,
grid: Grid,
atlas: Atlas,

pub const RendererSettings = struct {
    surface_height: u32,
    surface_width: u32,
    grid_rows: u32,
    grid_cols: u32,
};

pub fn init(
    allocator: Allocator,
    window_handles: win.WindowHandles,
    settings: RendererSettings,
) !Renderer {
    const atlas = try Atlas.create(allocator, 20, 20, 0, 128);

    const grid = try Grid.create(allocator, .{
        .rows = settings.grid_rows,
        .cols = settings.grid_cols,
    });

    const backend = try Backend.init(allocator, window_handles, settings);
    const cursor = try Cursor.init();

    return .{
        .backend = backend,
        .fps = try FPS.init(),
        .cursor = cursor,
        .grid = grid,
        .atlas = atlas,
    };
}

pub fn setup(self: *Renderer, window: *Window, allocator: Allocator) !void {
    try self.setup(window, allocator);
}

pub fn deinit(self: *Renderer) void {
    self.backend.deinit();
}

pub fn clearBuffer(self: *Renderer, clear_color: color.RGBA) void {
    self.backend.clearBuffer(clear_color);
}

pub fn presentBuffer(self: *Renderer) void {
    self.backend.presentBuffer();
}

pub fn renaderGrid(self: *Renderer) !void {
    try self.backend.renaderGrid();
}

pub fn setCell(
    self: *Renderer,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?color.RGBA,
    bg_color: ?color.RGBA,
) !void {
    try self.backend.setCell(row, col, char_code, fg_color, bg_color);
}

pub fn setCursorCell(self: *Renderer, char_code: u32) !void {
    try self.setCell(self.cursor.row, self.cursor.col, char_code, null, null);
    self.cursor.nextCol();
}

pub fn resize(self: *Renderer, width: u32, height: u32) !void {
    return self.backend.resize(width, height);
}

pub fn getFps(self: *Renderer) f64 {
    return self.fps.getFps();
}

pub const Api = @import("build_options").@"render-backend";

pub const Backend = switch (Api) {
    .opengl => @import("opengl/OpenGL.zig"),
    .d3d11 => @compileError("D3D11 is deprecated"),
    .vulkan => @import("vulkan/Backend.zig"),
};

pub const FPS = @import("common/FPS.zig");
pub const Atlas = @import("font").Atlas;
const Cursor = @import("cursor").Cursor;
const Grid = @import("grid").CellProgram;
const win = @import("window");
const Window = win.Window;
const Allocator = @import("std").mem.Allocator;
const color = @import("color");
