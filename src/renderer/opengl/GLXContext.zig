display: *c.x11.Display,
drawable: usize,
context: c.glx.GLXContext,
glXSwapIntervalsEXT: PFNGLXSWAPINTERVALEXTPROC,
glXSwapBuffers: PFNGLXSWAPBUFFERSPROC,

pub const CreateOpenGLContextError = error {
    GLXCreateContext,
};

pub fn createOpenGLContext(window: *Window) CreateOpenGLContextError!OpenGLContext {
    const display = window.display;
    const root = c.x11.DefaultRootWindow(display);

    var attr = [_]c_int{ c.glx.GLX_RGBA, c.glx.GLX_DEPTH_SIZE, 24, c.glx.GLX_DOUBLEBUFFER, c.glx.None };

    const vi = c.glx.glXChooseVisual(@ptrCast(display), 0, @ptrCast(&attr));

    var swa: c.x11.XSetWindowAttributes = undefined;

    swa.colormap = c.x11.XCreateColormap(@ptrCast(display), root, @ptrCast(vi.*.visual), c.x11.AllocNone);
    swa.event_mask = c.x11.ExposureMask | c.x11.KeyPressMask;

    window.w = c.x11.XCreateWindow(
        @ptrCast(display),
        root,
        0,
        0,
        window.width,
        window.height,
        0,
        vi.*.depth,
        c.glx.InputOutput,
        @ptrCast(vi.*.visual),
        c.glx.CWColormap | c.glx.CWEventMask,
        &swa,
    );

    const gl_context = c.glx.glXCreateContext(@ptrCast(display), vi, null, 1) orelse return error.GLXCreateContext;
    _ = c.glx.glXMakeCurrent(@ptrCast(display), window.w, gl_context);
    _ = c.glx.XMapWindow(@ptrCast(display), window.w);

    const glXSwapIntervalsEXT: PFNGLXSWAPINTERVALEXTPROC = @ptrCast(glXGetProcAddress("glXSwapIntervalsEXT"));
    const glXSwapBuffers: PFNGLXSWAPBUFFERSPROC = @ptrCast(glXGetProcAddress("glXSwapBuffers"));

    return .{
        .display = @ptrCast(display),
        .drawable = window.w,
        .context = gl_context,
        .glXSwapIntervalsEXT = glXSwapIntervalsEXT,
        .glXSwapBuffers = glXSwapBuffers,
    };
}

pub fn swapBuffers(self: *OpenGLContext) void {
    self.glXSwapBuffers(@ptrCast(self.display), self.drawable);
}

pub fn destory(self: *OpenGLContext) void {
    _ = c.glx.glXMakeCurrent(@ptrCast(self.display), c.glx.None, null);
    _ = c.glx.glXDestroyContext(@ptrCast(self.display), self.context);
}

const std = @import("std");
const gl = @import("gl");

const c = struct {
    const x11 = @cImport({
        @cInclude("X11/Xlib.h");
    });

    const gl = @cImport({
        @cInclude("GL/gl.h");
    });

    const glx = @cImport({
        @cInclude("GL/glx.h");
    });
};

const PFNGLXCREATECONTEXTATTRIBSARBPROC = *const fn (
    dpy: *c.x11.Display,
    config: c.glx.GLXFBConfig,
    share_context: ?*opaque {},
    direct: u32,
    attrib_list: [*:0]const u32,
) callconv(.C) c.glx.GLXContext;

pub const PFNGLXMAKECURRENTPROC = *const fn (
    display: ?*c.x11.Display,
    drawable: usize,
    ctx: ?*anyopaque,
) callconv(.C) c_int;

pub const PFNGLXSWAPBUFFERSPROC = *const fn (
    dpy: ?*c.x11.Display,
    drawable: usize,
) callconv(.C) void;

pub const PFNGLXSWAPINTERVALEXTPROC = *const fn (
    dpy: ?*c.x11.Display,
    drawable: usize,
    interval: c_int,
) callconv(.C) void;

extern "GL" fn glXGetProcAddress(procName: [*:0]const u8) callconv(.C) ?*const anyopaque;

pub const glGetProcAddress = glXGetProcAddress;

const OpenGLContext = @This();
const Window = @import("../../window/root.zig").Window;

const GLX_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const GLX_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const GLX_CONTEXT_FLAGS_ARB = 0x2094;
const GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;
