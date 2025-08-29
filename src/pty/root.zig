pub const ShellEnum = enum {
    cmd,
    pws,
    bash,
    zsh,
    defualt,

    fn toString(self: ShellEnum) []const u8 {
        return switch (self) {
            .cmd => "cmd",
            .pws => "powershell",
            .bash => "bash",
            .zsh => "zsh",
            else => {},
        };
    }
};

pub const PtySize = packed struct {
    width: u16,
    height: u16,
    // x_pixel: u16 = 0,
    // y_pixel: u16 = 0,
};

pub const PtyOptions = struct {
    shell: ?ShellEnum = null,
    shell_args: ?[]const u8 = null,
    async_io: bool = false,
    size: PtySize = .{ .height = 10, .width = 10 },
};

pub const Pty = switch (@import("builtin").os.tag) {
    .linux, .macos => @import("Posix.zig"),
    .windows => @import("Win32.zig"),
    else => @compileError("Pty is not implemented for this os"),
};

test Pty {
    var pty: Pty = undefined;
    try pty.open(.{});
    defer pty.close();

    try pty.resize(.{ .width = 10, .height = 10 });
}
