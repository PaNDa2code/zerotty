const Pty = @This();

master: Fd,
slave: Fd,
size: struct { height: u16, width: u16 },
id: u32,

pub fn open(self: *Pty, options: PtyOptions) !void {
    var master: i32 = undefined;
    var slave: i32 = undefined;

    var ws: posix.winsize = .{
        .row = @intCast(options.size.height),
        .col = @intCast(options.size.width),
        .xpixel = 0,
        .ypixel = 0,
    };

    try openpty.openpty(&master, &slave, null, null, null, &ws);

    errdefer {
        _ = posix.close(master);
        _ = posix.close(slave);
    }

    self.master = master;
    self.slave = slave;
}

pub fn close(self: *Pty) void {
    posix.close(self.master);
    // TODO: this is closed by the child process starting
    // posix.close(self.slave);
}

pub fn resize(self: *Pty, size: PtySize) !void {
    const ws: posix.winsize = .{
        .row = size.height,
        .col = size.width,
        .xpixel = 0,
        .ypixel = 0,
    };

    if (std.os.linux.ioctl(self.master, 0x5414, @intFromPtr(&ws)) < 0) {
        return error.PtyResizeFailed;
    }
}

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const openpty = switch (builtin.os.tag) {
    .linux => @import("openpty"),
    .macos => @cImport({
        @cInclude("pty.h");
    }),
    else => {},
};
const pty = @import("root.zig");
const PtySize = pty.PtySize;
const PtyOptions = pty.PtyOptions;

pub const Fd = posix.fd_t;
