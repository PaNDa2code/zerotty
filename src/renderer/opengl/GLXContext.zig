display: *c.x11.Display,
drawable: usize,
context: c.glx.GLXContext,
glXSwapIntervalsEXT: PFNGLXSWAPINTERVALEXTPROC,
glXSwapBuffers: PFNGLXSWAPBUFFERSPROC,

pub const CreateOpenGLContextError = error{
    GLXCreateContext,
};

var ctxErrorOccurred: std.atomic.Value(bool) = .init(false);

pub fn createOpenGLContext(window: *Window) CreateOpenGLContextError!OpenGLContext {
    const display: *c.glx.Display = @ptrCast(window.display);

    var glx_major: i32 = 0;
    var glx_minor: i32 = 0;
    if (c.glx.glXQueryVersion(display, @ptrCast(&glx_major), @ptrCast(&glx_minor)) == 0 or
        glx_major < 1 or
        (glx_major == 1 and glx_minor < 3))
    {
        std.debug.panic("GLX verstion 1.3 and above required, current is {}.{}", .{ glx_major, glx_minor });
    }

    const glXCreateContextAttribsARB: PFNGLXCREATECONTEXTATTRIBSARBPROC = @ptrCast(glXGetProcAddress("glXCreateContextAttribsARB"));
    const glXSwapIntervalsEXT: PFNGLXSWAPINTERVALEXTPROC = @ptrCast(glXGetProcAddress("glXSwapIntervalsEXT"));
    const glXSwapBuffers: PFNGLXSWAPBUFFERSPROC = @ptrCast(glXGetProcAddress("glXSwapBuffers"));

    const fbcs = getFBCs(display);
    defer _ = c.x11.XFree(@ptrCast(@constCast(fbcs.ptr)));

    const best_fbc_index = getBestFBCIndex(display, fbcs);

    const best_fbc = fbcs[best_fbc_index];

    const vi = c.glx.glXGetVisualFromFBConfig(display, best_fbc);
    defer _ = c.x11.XFree(vi);

    const root = c.x11.RootWindow(display, vi.*.screen);

    var swa: c.x11.XSetWindowAttributes = undefined;

    swa.colormap = c.x11.XCreateColormap(@ptrCast(display), root, @ptrCast(vi.*.visual), c.x11.AllocNone);
    defer _ = c.x11.XFreeColormap(@ptrCast(display), swa.colormap);

    swa.background_pixmap = c.x11.None;
    swa.border_pixel = 0;
    swa.background_pixel = 0;
    swa.event_mask = c.x11.CWColormap | c.x11.CWBorderPixel | c.x11.CWBackPixel | c.x11.CWEventMask;

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
        c.x11.CWColormap | c.x11.CWBorderPixel | c.x11.CWBackPixel | c.x11.CWEventMask,
        &swa,
    );

    if (window.w == 0)
        @panic("Failed to create Xlib Window");

    _ = c.x11.XMapWindow(@ptrCast(display), window.w);
    _ = c.x11.XSelectInput(@ptrCast(display), window.w, c.x11.ExposureMask | c.x11.KeyPressMask);

    const glx_exts_ptr: [*:0]const u8 = c.glx.glXQueryExtensionsString(@ptrCast(display), c.x11.DefaultScreen(display));
    const glx_exts_slice = std.mem.span(glx_exts_ptr);

    const old_handler: c.x11.XErrorHandler = c.x11.XSetErrorHandler(&ctxErrorHandler);

    var glx_context: c.glx.GLXContext = null;
    ctxErrorOccurred.store(false, .seq_cst);

    if (extentionSupported(glx_exts_slice, "GLX_ARB_create_context")) {
        var context_attrs = [_]c_int{
            c.glx.GLX_CONTEXT_PROFILE_MASK_ARB, c.glx.GLX_CONTEXT_CORE_PROFILE_BIT_ARB,
            GLX_CONTEXT_MAJOR_VERSION_ARB,      3,
            GLX_CONTEXT_MINOR_VERSION_ARB,      0,
            0,
        };

        glx_context = glXCreateContextAttribsARB(display, best_fbc, null, 1, @ptrCast(&context_attrs));

        _ = c.x11.XSync(@ptrCast(display), 0);

        if (glx_context != null and !ctxErrorOccurred.load(.seq_cst)) {
            std.log.debug("Created 3.0 context", .{});
        } else {
            std.log.debug("Failed to create GL 3.0 context", .{});
            context_attrs[4] = 1;
            glx_context = glXCreateContextAttribsARB(display, best_fbc, null, 1, @ptrCast(&context_attrs));
        }
    } else {
        glx_context = c.glx.glXCreateNewContext(display, best_fbc, c.glx.GLX_RGBA_TYPE, null, 1);
    }

    _ = c.x11.XSync(@ptrCast(display), 0);
    _ = c.x11.XSetErrorHandler(old_handler);

    _ = c.glx.glXMakeCurrent(@ptrCast(display), window.w, glx_context);

    return .{
        .display = @ptrCast(display),
        .drawable = window.w,
        .context = glx_context,
        .glXSwapIntervalsEXT = glXSwapIntervalsEXT,
        .glXSwapBuffers = glXSwapBuffers,
    };
}

// https://www.opengl.org/archives/resources/features/OGLextensions
fn extentionSupported(glx_exts: []const u8, ext: []const u8) bool {
    var iter = std.mem.tokenizeScalar(u8, glx_exts, ' ');
    while (iter.next()) |extention| {
        if (std.mem.eql(u8, extention, ext))
            return true;
    }
    return false;
}

fn ctxErrorHandler(_: ?*c.x11.Display, _: [*c]c.x11.XErrorEvent) callconv(.c) c_int {
    ctxErrorOccurred.store(true, .seq_cst);
    return 0;
}

fn getBestFBCIndex(display: *c.glx.Display, fbcs: []const c.glx.GLXFBConfig) usize {
    var best_fbc: i32 = -1;
    var worst_fbc: i32 = -1;
    var best_num_samp: i32 = -1;
    var worst_num_samp: i32 = 999;

    for (fbcs, 0..) |fbc, i| {
        const vi = c.glx.glXGetVisualFromFBConfig(display, fbc);
        defer _ = c.x11.XFree(vi);

        if (vi != null) {
            var samp_buf: i32 = undefined;
            var samples: i32 = undefined;
            _ = c.glx.glXGetFBConfigAttrib(display, fbc, c.glx.GLX_SAMPLE_BUFFERS, &samp_buf);
            _ = c.glx.glXGetFBConfigAttrib(display, fbc, c.glx.GLX_SAMPLES, &samples);

            // std.log.debug(
            //     "fbc[{}] => visual ID 0x{x}: SAMPLE_BUFFERS = {}, SAMPLES = {}",
            //     .{ i, vi.*.visualid, samp_buf, samples },
            // );

            if (best_fbc < 0 or samp_buf != 0 and samples > best_num_samp) {
                best_fbc = @intCast(i);
                best_num_samp = samples;
            }
            if (worst_fbc < 0 or samp_buf == 0 or samples < worst_num_samp) {
                worst_fbc = @intCast(i);
                worst_num_samp = samples;
            }
        }
    }

    // std.log.debug("best_fbc = fbc[{}]", .{best_fbc});
    return @intCast(best_fbc);
}

fn getFBCs(display: *c.glx.Display) []const c.glx.GLXFBConfig {
    const visual_attribs: []const c_int = &.{
        c.glx.GLX_X_RENDERABLE,  1,
        c.glx.GLX_DRAWABLE_TYPE, c.glx.GLX_WINDOW_BIT,
        c.glx.GLX_RENDER_TYPE,   c.glx.GLX_RGBA_BIT,
        c.glx.GLX_X_VISUAL_TYPE, c.glx.GLX_TRUE_COLOR,
        c.glx.GLX_RED_SIZE,      8,
        c.glx.GLX_GREEN_SIZE,    8,
        c.glx.GLX_BLUE_SIZE,     8,
        c.glx.GLX_ALPHA_SIZE,    8,
        c.glx.GLX_DEPTH_SIZE,    24,
        c.glx.GLX_STENCIL_SIZE,  8,
        c.glx.GLX_DOUBLEBUFFER,  1,
        0,
    };

    var fbc_count: u32 = undefined;
    const fbcs_ptr = c.glx.glXChooseFBConfig(@ptrCast(display), c.x11.DefaultScreen(display), @ptrCast(visual_attribs.ptr), @ptrCast(&fbc_count));
    return fbcs_ptr[0..@intCast(fbc_count)];
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
    dpy: *c.glx.Display,
    config: c.glx.GLXFBConfig,
    share_context: ?*opaque {},
    direct: u32,
    attrib_list: [*:0]const c_int,
) callconv(.c) c.glx.GLXContext;

pub const PFNGLXMAKECURRENTPROC = *const fn (
    display: ?*c.x11.Display,
    drawable: usize,
    ctx: ?*anyopaque,
) callconv(.c) c_int;

pub const PFNGLXSWAPBUFFERSPROC = *const fn (
    dpy: ?*c.x11.Display,
    drawable: usize,
) callconv(.c) void;

pub const PFNGLXSWAPINTERVALEXTPROC = *const fn (
    dpy: ?*c.x11.Display,
    drawable: usize,
    interval: c_int,
) callconv(.c) void;

extern "GL" fn glXGetProcAddress(procName: [*:0]const u8) callconv(.c) ?*const anyopaque;

pub const glGetProcAddress = glXGetProcAddress;

const OpenGLContext = @This();
const Window = @import("../../window/root.zig").Window;

const GLX_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const GLX_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const GLX_CONTEXT_FLAGS_ARB = 0x2094;
const GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;
