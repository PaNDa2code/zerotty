const Pty = @This();

/// child pipe sides
slave_read: HANDLE,
slave_write: HANDLE,

/// terminal pipe sides
master_read: HANDLE,
master_write: HANDLE,

h_pesudo_console: HPCON,

child: ?HANDLE,

size: struct { height: u16, width: u16 },
id: u32,

fn isInvaliedOrNull(handle: ?HANDLE) bool {
    return handle == null or handle == win32fnd.INVALID_HANDLE_VALUE;
}

pub fn open(self: *Pty, options: PtyOptions) !void {
    var stdin_read: ?HANDLE = undefined;
    var stdin_write: ?HANDLE = undefined;
    var stdout_read: ?HANDLE = undefined;
    var stdout_write: ?HANDLE = undefined;
    var h_pesudo_console: ?HPCON = undefined;

    if (win32pipe.CreatePipe(&stdin_read, &stdin_write, null, 0) == 0 or isInvaliedOrNull(stdin_read) or isInvaliedOrNull(stdin_write)) {
        return error.PipeCreationFailed;
    }
    if (win32pipe.CreatePipe(&stdout_read, &stdout_write, null, 0) == 0 or isInvaliedOrNull(stdout_read) or isInvaliedOrNull(stdout_write)) {
        return error.PipeCreationFailed;
    }

    const hresult = win32con.CreatePseudoConsole(
        .{ .X = @intCast(options.size.width), .Y = @intCast(options.size.height) },
        stdin_read,
        stdout_write,
        0,
        &h_pesudo_console,
    );

    if (win32.zig.FAILED(hresult) or isInvaliedOrNull(h_pesudo_console)) {
        return error.CreatePseudoConsoleFailed;
    }

    self.h_pesudo_console = h_pesudo_console.?;
    self.master_write = stdin_write.?;
    self.master_read = stdout_read.?;
    self.slave_write = stdout_write.?;
    self.slave_read = stdin_read.?;
}

pub fn close(self: *Pty) void {
    // no need to terminate the sub process, closing the HPCON will do.

    // need to drain the communication pipes before calling ClosePseudoConsole
    var bytes_avalable: u32 = 0;
    var bytes_left: u32 = 0;
    var bytes_read: u32 = 0;

    while (win32pipe.PeekNamedPipe(self.master_read, null, 0, null, &bytes_avalable, &bytes_left) != 0 and bytes_avalable > 0) {
        var buffer: [1024]u8 = undefined;
        const to_read = @min(buffer.len, bytes_avalable);
        _ = win32fs.ReadFile(self.master_read, &buffer, to_read, &bytes_read, null);
    }

    win32con.ClosePseudoConsole(self.h_pesudo_console);
}

pub fn resize(self: *Pty, size: PtySize) !void {
    const hresult = win32con.ResizePseudoConsole(self.h_pesudo_console, @bitCast(size));
    if (hresult < 0) {
        return error.PtyResizeFailed;
    }
}

const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");
const pty = @import("root.zig");
const PtySize = pty.PtySize;
const PtyOptions = pty.PtyOptions;

const L = std.unicode.utf8ToUtf16LeStringLiteral;
const W = std.unicode.utf8ToUtf16LeAllocZ;

const win32con = win32.system.console;
const win32fnd = win32.foundation;
const win32pipe = win32.system.pipes;
const win32sec = win32.security;
const win32thread = win32.system.threading;
const win32storeage = win32.storage;
const win32fs = win32storeage.file_system;
const win32mem = win32.system.memory;
const HANDLE = win32fnd.HANDLE;
const HPCON = win32con.HPCON;
