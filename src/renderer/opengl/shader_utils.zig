const std = @import("std");
const gl = @import("gl");

pub const CreateShaderProgramError = error{
    VertexShaderCompilationFailed,
    FragmentShaderCompilationFailed,
    ProgramLinkingFailed,
};

pub fn createShaderProgram(vert: [:0]const u8, frag: [:0]const u8) CreateShaderProgramError!c_uint {
    var stat: i32 = 0;

    const vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
    defer gl.DeleteShader(vertex_shader);

    gl.ShaderSource(vertex_shader, 1, &.{@ptrCast(vert.ptr)}, null);

    const fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    defer gl.DeleteShader(fragment_shader);

    gl.ShaderSource(fragment_shader, 1, &.{@ptrCast(frag.ptr)}, null);

    gl.CompileShader(vertex_shader);

    gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &stat);
    if (stat == gl.FALSE) {
        return error.VertexShaderCompilationFailed;
    }

    gl.CompileShader(fragment_shader);
    gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &stat);
    if (stat == gl.FALSE) {
        return error.FragmentShaderCompilationFailed;
    }

    const program = gl.CreateProgram();
    errdefer gl.DeleteProgram(program);

    gl.AttachShader(program, vertex_shader);
    gl.AttachShader(program, fragment_shader);

    gl.LinkProgram(program);

    gl.GetProgramiv(program, gl.LINK_STATUS, &stat);

    if (stat == gl.FALSE) {
        var log: [512]u8 = undefined;
        var log_len: gl.int = 0;
        gl.GetProgramInfoLog(program, 512, &log_len, &log);
        std.log.err("Shader link failed: {s}", .{log[0..@intCast(log_len)]});
        return error.ProgramLinkingFailed;
    }

    return program;
}
