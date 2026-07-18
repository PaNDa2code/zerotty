var webgl_context: ContextHandle = undefined;
var gl_proc: gl.ProcTable = undefined;

export fn main() c_int {
    init();
    emscripten_set_main_loop(frame, 1, 0);
    return 0;
}

export fn init() void {
    var context_attr = std.mem.zeroes(EmscriptenWebGLContextAttributes);
    emscripten_webgl_init_context_attributes(&context_attr);

    webgl_context = emscripten_webgl_create_context("#canvas", &context_attr);

    if (webgl_context == 0)
        @panic("emscripten_webgl_create_context: failed to create context");

    if (emscripten_webgl_make_context_current(webgl_context) < 0)
        @panic("emscripten_webgl_make_context_current: failed to set context");

    if (!gl_proc.init(eglGetProcAddress))
        @panic("failed to load opengl proc table");

    gl.makeProcTableCurrent(&gl_proc);
}

export fn frame() void {
    gl.ClearColor(0.3, 0.3, 0.3, 1);
    gl.Clear(gl.COLOR_BUFFER_BIT);
}

export fn destroy() void {
    _ = emscripten_webgl_make_context_current(0);
    _ = emscripten_webgl_destroy_context(webgl_context);
}

const std = @import("std");
const gl = @import("gl");

extern fn eglGetProcAddress(name: [*:0]const u8) ?*const anyopaque;

const ContextHandle = c_int;

extern fn emscripten_webgl_create_context(
    target: [*:0]const u8,
    attributes: *const EmscriptenWebGLContextAttributes,
) ContextHandle;

extern fn emscripten_set_main_loop(
    func: ?*const fn () callconv(.C) void,
    fps: c_int,
    simulate_infinite_loop: c_int,
) void;

extern fn emscripten_webgl_init_context_attributes(
    attributes: *EmscriptenWebGLContextAttributes,
) void;

extern fn emscripten_webgl_make_context_current(ctx: ContextHandle) c_int;

extern fn emscripten_webgl_destroy_context(ctx: ContextHandle) c_int;

const EmscriptenWebGLContextAttributes = extern struct {
    alpha: c_int,
    depth: c_int,
    stencil: c_int,
    antialias: c_int,
    premultipliedAlpha: c_int,
    preserveDrawingBuffer: c_int,
    preferLowPowerToHighPerformance: c_int,
    failIfMajorPerformanceCaveat: c_int,
    enableExtensionsByDefault: c_int,
    explicitSwapControl: c_int,
    proxyContextToMainThread: c_int,
    renderViaOffscreenBackBuffer: c_int,
    majorVersion: c_int,
    minorVersion: c_int,
    enableWebGL2CompatProfile: c_int,
    enableWebGLExtensions: c_int,
    enableWebGLDebugRendererInfo: c_int,
};
