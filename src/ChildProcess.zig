const ChildProcess = @This();

id: switch (os) {
    .windows => win32fnd.HANDLE,
    .macos, .linux => posix.pid_t,
    else => @compileError("os is not supported"),
} = switch (os) {
    .windows => win32fnd.INVALID_HANDLE_VALUE,
    .macos, .linux => 0,
    else => @compileError("os is not supported"),
},

exe_path: []const u8,
args: []const []const u8 = &.{""},
env_map: ?std.process.EnvMap = null,
cwd: ?[]const u8 = null,

stdin: ?File = null,
stdout: ?File = null,
stderr: ?File = null,

pub fn start(self: *ChildProcess, allocator: Allocator, pty: ?*Pty) !void {
    var arina = std.heap.ArenaAllocator.init(allocator);
    defer arina.deinit();

    return switch (os) {
        .windows => self.startWindows(arina.allocator(), pty),
        .linux, .macos => self.startPosix(arina.allocator(), pty),
        else => @compileError("Not supported"),
    };
}

pub fn terminate(self: *ChildProcess) void {
    switch (os) {
        .windows => self.terminateWindows(),
        .linux, .macos => self.terminatePosix(),
        else => @compileError("Not supported"),
    }
}

pub fn wait(self: *const ChildProcess) !void {
    return switch (os) {
        .windows => self.waitWindows(),
        .linux, .macos => self.waitPosix(),
        else => @compileError("Not supported"),
    };
}

pub fn deinit(self: *ChildProcess) void {
    if (self.env_map) |*map| map.deinit();
    self.* = .{ .exe_path = "" };
}

fn startWindows(self: *ChildProcess, arina: Allocator, pty: ?*Pty) !void {
    var startup_info_ex = std.mem.zeroes(win32thread.STARTUPINFOEXW);
    startup_info_ex.StartupInfo.cb = @sizeOf(win32thread.STARTUPINFOEXW);

    if (pty) |_pty| {
        var bytes_required: usize = 0;
        // ignored because it always fails
        _ = win32thread.InitializeProcThreadAttributeList(null, 1, 0, &bytes_required);

        const buffer = try arina.alloc(u8, bytes_required);

        startup_info_ex.lpAttributeList = @ptrCast(buffer.ptr);

        if (win32thread.InitializeProcThreadAttributeList(startup_info_ex.lpAttributeList, 1, 0, &bytes_required) == 0) {
            return error.InitializeProcThreadAttributeListFailed;
        }

        if (win32thread.UpdateProcThreadAttribute(
            startup_info_ex.lpAttributeList,
            0,
            win32thread.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            _pty.h_pesudo_console,
            @sizeOf(win32con.HPCON),
            null,
            null,
        ) == 0) {
            return error.UpdateProcThreadAttributeFailed;
        }
        self.stdin = .{ .handle = _pty.master_write };
        self.stdout = .{ .handle = _pty.master_read };
        self.stderr = .{ .handle = _pty.master_read };
    }

    var proc_info = std.mem.zeroes(win32thread.PROCESS_INFORMATION);

    const path = try findPathAlloc(arina, self.exe_path) orelse self.exe_path;

    const path_absolute =
        if (std.fs.path.isAbsoluteWindows(path))
            path
        else
            try std.fs.realpathAlloc(arina, path);

    const pathW = try std.unicode.utf8ToUtf16LeAllocZ(arina, path_absolute);

    const cwd = if (self.cwd) |cwd_path| (try std.unicode.utf8ToUtf16LeAllocZ(arina, cwd_path)).ptr else null;

    var env_block: ?*anyopaque = null;
    if (self.env_map) |envmap| {
        var buffer = try std.ArrayList(u8).initCapacity(arina, 1024);
        var writer = buffer.writer(arina);

        var it = envmap.iterator();
        while (it.next()) |entry| {
            try writer.print("{}={}\x00", .{ entry.key_ptr, entry.value_ptr });
        }
        try writer.writeByte(0);
        env_block = buffer.items.ptr;
    }

    if (win32thread.CreateProcessW(
        pathW.ptr,
        null,
        null,
        null,
        0,
        if (pty != null) .{ .EXTENDED_STARTUPINFO_PRESENT = 1 } else .{},
        env_block,
        cwd,
        if (pty != null) &startup_info_ex.StartupInfo else null,
        &proc_info,
    ) == 0) {
        return error.CreateProcessWFailed;
    }

    self.id = proc_info.hProcess.?;
    if (pty) |_pty| {
        _pty.child = proc_info.hProcess.?;
    }
}

fn terminateWindows(self: *ChildProcess) void {
    _ = win32thread.TerminateProcess(self.id, 0);
}

fn waitWindows(self: *const ChildProcess) !void {
    if (win32thread.WaitForSingleObject(self.id, std.math.maxInt(u32)) != 0) {
        return error.WatingFailed;
    }
}

fn startPosix(self: *ChildProcess, arina: std.mem.Allocator, pty: ?*Pty) !void {
    const slave_fd = pty.?.slave;
    const master_fd = pty.?.master;

    const path = try findPathAlloc(arina, self.exe_path) orelse self.exe_path;
    const path_absolute =
        if (std.fs.path.isAbsolutePosix(path))
            path
        else
            try std.fs.realpathAlloc(arina, path);
    const pathZ = try arina.dupeZ(u8, path_absolute);
    const argsZ = try arina.allocSentinel(?[*:0]u8, self.args.len, null);
    for (self.args, 0..) |arg, i| {
        argsZ[i] = try arina.dupeZ(u8, arg);
    }

    const env_map = self.env_map orelse try std.process.getEnvMap(arina);
    const envZ: [*:null]const ?[*:0]u8 = envz: {
        const envZ = try arina.allocSentinel(?[*:0]u8, env_map.count(), null);
        var it = env_map.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            envZ[i] = try std.fmt.allocPrintSentinel(
                arina,
                "{s}={s}",
                .{ entry.key_ptr.*, entry.value_ptr.* },
                0,
            );
        }
        break :envz envZ.ptr;
    };

    const pid = try posix.fork();

    if (pid != 0) {
        self.stdin = .{ .handle = master_fd };
        self.stdout = .{ .handle = master_fd };
        self.stderr = .{ .handle = master_fd };
        self.id = pid;
        posix.close(slave_fd);
        pty.?.child = pid;
        return;
    }

    // TODO: implement macOS syscalls
    _ = linux.setsid();
    _ = linux.ioctl(slave_fd, 0x540E, @as(usize, 0));

    try posix.dup2(slave_fd, posix.STDIN_FILENO);
    try posix.dup2(slave_fd, posix.STDOUT_FILENO);
    try posix.dup2(slave_fd, posix.STDERR_FILENO);

    posix.close(master_fd);
    posix.close(slave_fd);

    posix.execveZ(pathZ, argsZ, envZ) catch {
        posix.exit(127);
    };
}

fn terminatePosix(self: *ChildProcess) void {
    _ = posix.kill(self.id, posix.SIG.KILL) catch {};
}

fn waitPosix(self: *const ChildProcess) !void {
    _ = posix.waitpid(self.id, 0);
}

fn findPathAlloc(allocator: Allocator, exe: []const u8) !?[]const u8 {
    const sep = std.fs.path.sep;
    const delimiter = std.fs.path.delimiter;

    if (std.mem.containsAtLeastScalar(u8, exe, 1, sep)) return exe;

    const suffix =
        if (os == .windows and !std.mem.endsWith(u8, exe, ".exe"))
            ".exe"
        else
            "";

    const PATH = try std.process.getEnvVarOwned(allocator, "PATH");
    defer allocator.free(PATH);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var it = std.mem.tokenizeScalar(u8, PATH, delimiter);

    while (it.next()) |search_path| {
        const full_path = try std.fmt.bufPrintZ(&path_buf, "{s}{c}{s}{s}", .{ search_path, sep, exe, suffix });
        const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound, error.AccessDenied => continue,
                else => return err,
            }
        };
        defer file.close();
        const stat = try file.stat();
        if (stat.kind != .directory and (os == .windows or stat.mode & 0o0111 != 0)) {
            return try allocator.dupe(u8, full_path);
        }
    }

    return null;
}

pub fn setEnvVar(self: *ChildProcess, allocator: Allocator, name: []const u8, value: []const u8) !void {
    if (self.env_map == null) {
        self.env_map = .init(allocator);
    }
    try self.env_map.?.put(name, value);
}

pub fn unsetEvnVar(self: *ChildProcess, name: []const u8) void {
    if (self.env_map) |*map| {
        map.remove(name);
    }
}

test ChildProcess {
    var pty: Pty = undefined;
    try pty.open(.{
        .size = .{ .height = 100, .width = 100 },
    });
    defer pty.close();

    var child: ChildProcess = .{
        .exe_path = if (os == .windows) "cmd" else "bash",
        .args = &.{},
    };

    try child.start(std.testing.allocator, &pty);
    defer child.terminate();
    // try child.wait();
}

const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;

const win32con = win32.system.console;
const win32fnd = win32.foundation;
const win32pipe = win32.system.pipes;
const win32sec = win32.security;
const win32thread = win32.system.threading;
const win32fs = win32.storage.file_system;
const win32mem = win32.system.memory;

const Pty = @import("pty").Pty;

const File = std.fs.File;
const Allocator = std.mem.Allocator;

const os = builtin.os.tag;
