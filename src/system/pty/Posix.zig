const Pty = @This();

master: Fd,
slave: Fd,
size: PtySize,

pub fn open(options: PtyOptions) !Pty {
    var master: i32 = -1;
    var slave: i32 = -1;

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

    if (builtin.os.tag == .linux) {
        // SET O_NONBLOCK flag
        const master_flags = std.os.linux.fcntl(master, 3, 0);
        _ = std.os.linux.fcntl(master, 4, master_flags | 0x0080);
    }

    return .{
        .master = master,
        .slave = slave,
        .size = options.size,
    };
}

pub fn close(self: *Pty) void {
    _ = std.os.linux.close(self.master);
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

    const err =
        std.posix.system.ioctl(self.master, std.posix.system.T.IOCSWINSZ, @intFromPtr(&ws));

    if (err < 0)
        return error.PtyResizeFailed;
}

pub fn readFile(self: *const Pty) std.Io.File {
    return std.Io.File{
        .handle = self.master,
        .flags = .{ .nonblocking = builtin.os.tag == .linux },
    };
}

pub fn writeFile(self: *const Pty) std.Io.File {
    return std.Io.File{
        .handle = self.master,
        .flags = .{ .nonblocking = builtin.os.tag == .linux },
    };
}

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const openpty = @import("openpty");
const pty = @import("root.zig");
const PtySize = pty.PtySize;
const PtyOptions = pty.PtyOptions;

pub const Fd = posix.fd_t;
