pub const Api = @import("build_options").@"window-system";

pub const Window = switch (Api) {
    .win32 => @import("Win32.zig"),
    .xlib => @import("Xlib.zig"),
    .xcb => @import("Xcb.zig"),
    .glfw => @import("GLFW.zig"),
    .android => @import("Android.zig"),
};
