//! Pty + Childprocess + Emulator
const Session = @This();

const std = @import("std");
const zerotty = @import("zerotty");
const Pty = zerotty.system.pty.Pty;
const Process = zerotty.system.Process;

pub const Status = enum(u8) { running = 0, idle, killed };

pty: Pty,
shell: Process,

status: std.atomic.Value(Status) = .init(.idle),

pub fn init(
    io: std.Io,
    env: *std.process.Environ.Map,
    allocator: std.mem.Allocator,
    shell_path: []const u8,
    shell_args: []const []const u8,
    pty_rows: u16,
    pty_columns: u16,
) !Session {
    var pty = try Pty.open(.{
        .async_io = true,
        .size = .{
            .height = pty_rows,
            .width = pty_columns,
        },
    });
    errdefer pty.close();

    const shell = try Process.start(io, allocator, .{
        .exe_path = shell_path,
        .exe_args = shell_args,
        .environ_map = env,
        .pty = pty,
    });

    return .{
        .pty = pty,
        .shell = shell,
        .status = .init(.running),
    };
}

pub fn deinit(session: *Session) void {
    if (session.status.swap(.killed, .acq_rel) == .running) return;

    session.shell.terminate();

    _ = session.shell.wait(true) catch {};

    session.shell.deinit();
    session.pty.close();
}

pub fn resize(session: *Session, rows: u16, columns: u16) !void {
    try session.pty.resize(.{
        .height = rows,
        .width = columns,
    });
}

pub fn isRunning(session: *const Session) bool {
    return session.status.load(.acq_rel) == .running;
}

pub fn writer(session: *const Session, io: std.Io, buf: []u8) !std.Io.Writer {
    try session.pty.writeFile().writer(io, buf);
}

pub fn reader(session: *const Session, io: std.Io, buf: []u8) !std.Io.Reader {
    try session.pty.readFile().reader(io, buf);
}

pub fn writeAll(
    session: *const Session,
    io: std.Io,
    bytes: []const u8,
) std.Io.Writer.Error!void {
    try session.writer(io, &.{}).writeAll(bytes);
}
