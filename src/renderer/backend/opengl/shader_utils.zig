const std = @import("std");
const gl = @import("gl");

pub const CreateShaderProgramError = error{
    VertexShaderCompilationFailed,
    FragmentShaderCompilationFailed,
    ProgramLinkingFailed,
};

pub fn createShaderProgram(vert_spv: [:0]const u8, frag_spv: [:0]const u8) CreateShaderProgramError!c_uint {
    var stat: i32 = 0;

    const vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
    defer gl.DeleteShader(vertex_shader);

    gl.ShaderBinary(1, @ptrCast(&vertex_shader), gl.SHADER_BINARY_FORMAT_SPIR_V_ARB, vert_spv.ptr, @intCast(vert_spv.len));
    gl.SpecializeShaderARB(vertex_shader, "main", 0, null, null);

    gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &stat);
    if (stat == gl.FALSE) {
        return error.VertexShaderCompilationFailed;
    }

    const fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    defer gl.DeleteShader(fragment_shader);

    gl.ShaderBinary(1, @ptrCast(&fragment_shader), gl.SHADER_BINARY_FORMAT_SPIR_V_ARB, frag_spv.ptr, @intCast(frag_spv.len));
    gl.SpecializeShaderARB(fragment_shader, "main", 0, null, null);

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
