pub const Api = @import("build_options").@"window-system";

pub const Window = switch (@import("build_options").@"window-system") {
    .Win32 => @import("Win32.zig"),
    .Xlib => @import("Xlib.zig"),
    .Xcb => @import("Xcb.zig"),
};
