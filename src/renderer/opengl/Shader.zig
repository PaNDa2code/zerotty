const ShaderProgram = @This();

program: gl.uint,

pub const ShaderType = enum(gl.uint) {
    Vertex = gl.VERTEX_SHADER,
    Fragment = gl.FRAGMENT_SHADER,
    Geometry = gl.GEOMETRY_SHADER,
    TessControl = gl.TESS_CONTROL_SHADER,
    TessEvaluation = gl.TESS_EVALUATION_SHADER,
};

pub fn init() ShaderProgram {
    const program = gl.CreateProgram();

    return .{ .program = program };
}

pub fn deinit(self: *ShaderProgram) void {
    gl.DeleteProgram(self.program);
    self.program = 0;
}

pub fn attachShaderSPIRV(self: *const ShaderProgram, buffer: []const u8, shader_type: ShaderType) !void {
    const shader = gl.CreateShader(@intFromEnum(shader_type));

    gl.ShaderBinary(1, @ptrCast(&shader), gl.SHADER_BINARY_FORMAT_SPIR_V_ARB, buffer.ptr, @intCast(buffer.len));
    gl.SpecializeShaderARB(shader, "main", 0, null, null);

    var stat: i32 = 0;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &stat);
    if (stat == gl.FALSE) {
        return error.VertexShaderCompilationFailed;
    }

    gl.AttachShader(self.program, shader);
}

pub fn linkProgram(self: *const ShaderProgram) void {
    var buf: [6]gl.uint = undefined;
    var len: c_int = undefined;
    gl.GetAttachedShaders(self.program, buf.len, &len, &buf);

    gl.LinkProgram(self.program);

    for (buf[0..@intCast(len)]) |shd|
        gl.DeleteShader(shd);
}

pub fn useProgram(self: *const ShaderProgram) void {
    gl.UseProgram(self.program);
}

const gl = @import("gl");
