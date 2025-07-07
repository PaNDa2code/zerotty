pub const Api = @import("build_options").@"window-system";

pub const Window = switch (Api) {
    .Win32 => @import("Win32.zig"),
    .Xlib => @import("Xlib.zig"),
    .Xcb => @import("Xcb.zig"),
};
