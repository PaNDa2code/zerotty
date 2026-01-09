device_context: HDC,
opengl_rendering_context: HGLRC,
window_handle: HWND,
wglSwapIntervalEXT: PFNWGLSWAPINTERVALEXTPROC,

pub const CreateOpenGLContextError = error{
    RegisterClass,
    CreateWindow,
    GetDC,
    ChoosePixelFormat,
    SetPixelFormat,
    WglCreateContext,
    WglMakeCurrent,
    WglChoosePixelFormatARB,
    WglCreateContextAttribsARB,
    DescribePixelFormat,
};

pub fn createOpenGLContext(window: *Window) CreateOpenGLContextError!OpenGLContext {
    const dummy_window_class_name = std.unicode.wtf8ToWtf16LeStringLiteral("Core");
    const dummy_window_class = std.mem.zeroInit(windows.WNDCLASSW, .{
        .lpszClassName = dummy_window_class_name,
        .style = .{ .OWNDC = 1, .VREDRAW = 1, .HREDRAW = 1 },
        .lpfnWndProc = windows.DefWindowProcW,
        .hInstance = lib_loader.GetModuleHandleW(null),
    });

    _ = windows.RegisterClassW(&dummy_window_class);

    const dummy_window = windows.CreateWindowExW(
        .{},
        dummy_window_class_name,
        std.unicode.wtf8ToWtf16LeStringLiteral("FakeWindow"),
        .{ .CLIPSIBLINGS = 1, .CLIPCHILDREN = 1 },
        0,
        0,
        1,
        1,
        null,
        null,
        dummy_window_class.hInstance,
        null,
    );

    const dummy_dc = gdi.GetDC(dummy_window);

    const temp_pf_disc = std.mem.zeroInit(open_gl.PIXELFORMATDESCRIPTOR, .{
        .nSize = @sizeOf(open_gl.PIXELFORMATDESCRIPTOR),
        .nVersion = 1,
        .dwFlags = .{ .DRAW_TO_WINDOW = 1, .SUPPORT_OPENGL = 1, .DOUBLEBUFFER = 1 },
        .iPixelType = .RGBA,
        .cColorBits = 32,
        .cAlphaBits = 8,
        .cDepthBits = 24,
    });

    const temp_format = open_gl.ChoosePixelFormat(dummy_dc, &temp_pf_disc);

    if (temp_format == 0) {
        return error.ChoosePixelFormat;
    }

    if (open_gl.SetPixelFormat(dummy_dc, temp_format, &temp_pf_disc) == 0) {
        return error.SetPixelFormat;
    }

    const dummy_rc = open_gl.wglCreateContext(dummy_dc);

    if (dummy_rc == null) {
        return error.WglCreateContext;
    }

    if (open_gl.wglMakeCurrent(dummy_dc, dummy_rc) == 0) {
        return error.WglMakeCurrent;
    }

    const wglChoosePixelFormatARB: PFNWGLCHOOSEPIXELFORMATARBPROC =
        @ptrCast(open_gl.wglGetProcAddress("wglChoosePixelFormatARB") orelse @panic("can't load wglChoosePixelFormatARB"));

    const wglCreateContextAttribsARB: PFNWGLCREATECONTEXTATTRIBSARBPROC =
        @ptrCast(open_gl.wglGetProcAddress("wglCreateContextAttribsARB") orelse @panic("can't load wglCreateContextAttribsARB"));

    const pixel_attribus = [_]i32{
        WGL_DRAW_TO_WINDOW_ARB, GL_TRUE,
        WGL_SUPPORT_OPENGL_ARB, GL_TRUE,
        WGL_DOUBLE_BUFFER_ARB,  GL_TRUE,
        WGL_PIXEL_TYPE_ARB,     WGL_TYPE_RGBA_ARB,
        WGL_ACCELERATION_ARB,   WGL_FULL_ACCELERATION_ARB,
        WGL_COLOR_BITS_ARB,     32,
        WGL_ALPHA_BITS_ARB,     8,
        WGL_DEPTH_BITS_ARB,     24,
        WGL_STENCIL_BITS_ARB,   8,
        WGL_SAMPLE_BUFFERS_ARB, GL_TRUE,
        WGL_SAMPLES_ARB,        4,
        0,
    };

    var pixel_format_id: i32 = 0;
    var num_formats: u32 = 0;

    const dc = gdi.GetDC(window.hwnd) orelse return error.GetDC;

    const status = wglChoosePixelFormatARB(
        dc,
        @ptrCast(&pixel_attribus),
        null,
        1,
        @ptrCast(&pixel_format_id),
        &num_formats,
    ) != 0;

    if (!status or num_formats == 0 or pixel_format_id == 0) {
        return error.WglChoosePixelFormatARB;
    }

    var pfd: open_gl.PIXELFORMATDESCRIPTOR = undefined;

    @setRuntimeSafety(false);
    _ = open_gl.DescribePixelFormat(
        dc,
        @enumFromInt(pixel_format_id),
        @sizeOf(open_gl.PIXELFORMATDESCRIPTOR),
        &pfd,
    );
    @setRuntimeSafety(true);

    if (open_gl.SetPixelFormat(dc, pixel_format_id, &pfd) == 0) {
        return error.SetPixelFormat;
    }

    const context_attribs = [_]i32{
        WGL_CONTEXT_MAJOR_VERSION_ARB, gl.info.version_major,
        WGL_CONTEXT_MINOR_VERSION_ARB, gl.info.version_minor,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        WGL_CONTEXT_FLAGS_ARB,         WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
        0,
    };

    const rc = wglCreateContextAttribsARB(dc, null, &context_attribs);

    if (rc == null) {
        return error.WglCreateContextAttribsARB;
    }

    _ = open_gl.wglMakeCurrent(null, null);
    _ = open_gl.wglDeleteContext(dummy_rc);
    _ = gdi.ReleaseDC(dummy_window, dummy_dc);
    _ = windows.DestroyWindow(dummy_window);
    _ = windows.UnregisterClassW(dummy_window_class_name, dummy_window_class.hInstance);

    if (open_gl.wglMakeCurrent(dc, rc) == 0) {
        return error.WglMakeCurrent;
    }

    const wglSwapIntervalEXT: PFNWGLSWAPINTERVALEXTPROC =
        @ptrCast(open_gl.wglGetProcAddress("wglSwapIntervalEXT") orelse @panic("can't load wglSwapIntervalEXT"));

    wglSwapIntervalEXT(1);

    return .{
        .device_context = dc,
        .opengl_rendering_context = rc.?,
        .window_handle = window.hwnd,
        .wglSwapIntervalEXT = wglSwapIntervalEXT,
    };
}

pub fn swapBuffers(self: *OpenGLContext) void {
    _ = open_gl.SwapBuffers(self.device_context);
}

pub fn destroy(self: *OpenGLContext) void {
    _ = open_gl.wglMakeCurrent(null, null);
    _ = gdi.ReleaseDC(self.window_handle, self.device_context);
}

const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
const WGL_SUPPORT_OPENGL_ARB = 0x2010;
const WGL_DOUBLE_BUFFER_ARB = 0x2011;
const WGL_PIXEL_TYPE_ARB = 0x2013;
const WGL_TYPE_RGBA_ARB = 0x202B;
const WGL_ACCELERATION_ARB = 0x2003;
const WGL_FULL_ACCELERATION_ARB = 0x2027;
const WGL_COLOR_BITS_ARB = 0x2014;
const WGL_ALPHA_BITS_ARB = 0x201B;
const WGL_DEPTH_BITS_ARB = 0x2022;
const WGL_STENCIL_BITS_ARB = 0x2023;
const WGL_SAMPLE_BUFFERS_ARB = 0x2041;
const WGL_SAMPLES_ARB = 0x2042;

const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const WGL_CONTEXT_LAYER_PLANE_ARB = 0x2093;
const WGL_CONTEXT_FLAGS_ARB = 0x2094;
const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;

const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;

const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;

const GL_FALSE: u32 = 0;
const GL_TRUE: u32 = 1;

const std = @import("std");
const gl = @import("gl");

const win32 = @import("win32");
const windows = win32.ui.windows_and_messaging;
const open_gl = win32.graphics.open_gl;
const lib_loader = win32.system.library_loader;
const gdi = win32.graphics.gdi;

const PFNWGLCHOOSEPIXELFORMATARBPROC = *const fn (
    hdc: gdi.HDC,
    piAttribIList: ?[*]const i32,
    pfAttribFList: ?[*]const f32,
    nMaxFormats: u32,
    piFormats: ?[*]i32,
    nNumFormats: ?*u32,
) callconv(.winapi) i32;

const PFNWGLCREATECONTEXTATTRIBSARBPROC = *const fn (
    hDC: gdi.HDC,
    hShareContext: ?win32.graphics.open_gl.HGLRC,
    attribList: ?[*]const i32,
) callconv(.winapi) ?win32.graphics.open_gl.HGLRC;

const PFNWGLSWAPINTERVALEXTPROC = *const fn (interval: i32) callconv(.winapi) void;

pub const HDC = gdi.HDC;
pub const HGLRC = open_gl.HGLRC;
pub const HWND = win32.foundation.HWND;

const OpenGLContext = @This();
const Window = @import("../../../window/root.zig").Window;

pub const glGetProcAddress = open_gl.wglGetProcAddress;
