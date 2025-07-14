const std = @import("std");
const ProcTable = @import("gl").ProcTable;

const DynamicLibrary = @import("../../DynamicLibrary.zig");

const opengl_lib_name = switch (@import("builtin").os.tag) {
    .windows => "opengl32.dll",
    .linux => "libGL.so",
    else => {},
};

pub fn createProcTable(allocator: std.mem.Allocator) !*ProcTable {
    const proc_table = try allocator.create(ProcTable);

    const gl_lib = DynamicLibrary.init(opengl_lib_name) catch
        @panic("can't load OpenGL library");

    if (!proc_table.init(gl_lib))
        @panic("opengl proc table loading failed");

    return proc_table;
}
