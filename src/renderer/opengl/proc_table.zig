const std = @import("std");
const ProcTable = @import("gl").ProcTable;

const DynamicLibrary = @import("../../DynamicLibrary.zig");

const os = @import("builtin").os.tag;

const opengl_lib_name = switch (os) {
    .windows => "opengl32.dll",
    .linux => "libGL.so",
    else => {},
};

const glGetProcAddress = switch (os) {
    .windows => @import("WGLContext.zig"),
    .linux => @import("GLXContext.zig"),
    else => {},
}.glGetProcAddress;

const Loader = struct {
    gl_lib: DynamicLibrary,
    glGetProcAddress: *const fn ([*:0]const u8) callconv(.C) isize = @ptrCast(&glGetProcAddress),

    pub fn getProcAddress(self: *const Loader, name: [*:0]const u8) ?*const anyopaque {
        const address = self.glGetProcAddress(name);
        return switch (address) {
            -1...3 => self.gl_lib.getProcAddress(name),
            else => @ptrFromInt(@as(usize, @bitCast(address))),
        };
    }
};

pub fn createProcTable(allocator: std.mem.Allocator) !*ProcTable {
    const proc_table = try allocator.create(ProcTable);

    const gl_lib = DynamicLibrary.init(opengl_lib_name) catch
        @panic("can't load OpenGL library");

    if (!proc_table.init(Loader{ .gl_lib = gl_lib }))
        @panic("opengl proc table loading failed");

    return proc_table;
}
