const OpenGL = @This();

const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const win = @import("window");
const gl = @import("gl");

context: OpenGLContext,

pub const InitError = std.mem.Allocator.Error ||
    OpenGLContext.CreateOpenGLContextError ||
    error{};

pub fn init(
    alloc: std.mem.Allocator,
    window_handles: win.WindowHandles,
    window_reqs: win.WindowRequirements,
    settings: root.RendererSettings,
) InitError!*OpenGL {
    _ = settings;

    const self = try alloc.create(OpenGL);

    self.context = try OpenGLContext.createOpenGLContext(
        window_handles,
        window_reqs,
    );

    const proc_table = try createProcTable(alloc, &OpenGLContext.glGetProcAddress);
    gl.makeProcTableCurrent(proc_table);

    return self;
}

pub fn deinit(self: *OpenGL) void {
    self.context.destroy();
}

const createProcTable = @import("opengl/proc_table.zig").createProcTable;

const OpenGLContext = switch (builtin.os.tag) {
    .windows => @import("opengl/WGLContext.zig"),
    .linux => @import("opengl/GLXContext.zig"),
    else => void,
};
