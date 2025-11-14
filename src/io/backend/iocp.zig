pub const Context = struct {
    const Self = @This();

    iocp: windows.HANDLE,

    pub fn setup(self: *Self) !void {
        self.iocp =
            try CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0);
    }

    pub fn close(self: *const Self) void {
        CloseHandle(self.iocp);
    }

    pub fn register(self: *const Self, req: *const Request) !void {
        _ = try CreateIoCompletionPort(req.handle, self.iocp, @intFromPtr(req), 0);
    }

    /// The `Request` must outlive its dequeuing.
    pub fn queue(self: *const Self, req: *const Request) !void {
        _ = self;

        const cb_ptr: *ControlBlock = @constCast(&req.control_block);

        const ret = switch (req.op_data) {
            .read => |buf| ReadFile(req.handle, buf.ptr, @intCast(buf.len), null, cb_ptr),
            .write => |buf| WriteFile(req.handle, buf.ptr, @intCast(buf.len), null, cb_ptr),
            .none => 1,
        };

        if (ret == 0) {
            return switch (windows.GetLastError()) {
                .IO_PENDING => {},
                .INVALID_USER_BUFFER => error.SystemResources,
                .NOT_ENOUGH_MEMORY => error.SystemResources,
                .OPERATION_ABORTED => error.OperationAborted,
                .NOT_ENOUGH_QUOTA => error.SystemResources,
                .NO_DATA => error.BrokenPipe,
                .INVALID_HANDLE => error.NotOpenForWriting,
                .LOCK_VIOLATION => error.LockViolation,
                .NETNAME_DELETED => error.ConnectionResetByPeer,
                .ACCESS_DENIED => error.AccessDenied,
                .WORKING_SET_QUOTA => error.SystemResources,
                else => |err| windows.unexpectedError(err),
            };
        }
    }

    pub fn submit(self: *const Self) !void {
        _ = self;
    }

    pub fn dequeue(self: *const Self, res: *i32) !*const Request {
        return (try self.dequeue_timeout(INFINITE, res)) orelse unreachable;
    }

    pub fn dequeue_timeout(self: *const Self, timeout_ms: u32, res: *i32) !?*const Request {
        var bytes: u32 = 0;
        var overlapped: ?*OVERLAPPED = null;
        var request_address: usize = 0;
        const stat = GetQueuedCompletionStatus(
            self.iocp,
            &bytes,
            &request_address,
            &overlapped,
            timeout_ms,
        );

        switch (stat) {
            .Normal => {
                res.* = @intCast(bytes);
                return @ptrFromInt(request_address);
            },
            .Timeout => return null,
            else => return windows.unexpectedError(windows.GetLastError()),
        }
    }
};

pub const ControlBlock = OVERLAPPED;

const root = @import("../root.zig");
const Request = root.Request;
const Operation = root.Operation;
const Result = root.Result;

const windows = @import("std").os.windows;
const kernel32 = windows.kernel32;
const HANDLE = windows.HANDLE;
const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
const INFINITE = windows.INFINITE;
const OVERLAPPED = windows.OVERLAPPED;
const CreateIoCompletionPort = windows.CreateIoCompletionPort;
const GetQueuedCompletionStatus = windows.GetQueuedCompletionStatus;
const CloseHandle = windows.CloseHandle;
const ReadFile = kernel32.ReadFile;
const WriteFile = kernel32.WriteFile;

test "iocp overlapped pipe write test (Windows)" {
    const std = @import("std");

    var context: Context = undefined;
    try context.setup();
    defer context.close();

    const pipe_name_w = std.unicode.utf8ToUtf16LeStringLiteral("\\\\.\\pipe\\zig_test_pipe");

    // Create server pipe (overlapped)
    const server = kernel32.CreateNamedPipeW(
        pipe_name_w.ptr,
        windows.PIPE_ACCESS_INBOUND | windows.FILE_FLAG_OVERLAPPED,
        windows.PIPE_TYPE_BYTE | windows.PIPE_NOWAIT,
        1,
        4096,
        4096,
        0,
        null,
    );
    if (server == windows.INVALID_HANDLE_VALUE) return error.PipeCreationFailed;
    defer _ = windows.CloseHandle(server);

    // Create client pipe (overlapped)
    const client = kernel32.CreateFileW(
        pipe_name_w.ptr,
        windows.GENERIC_WRITE,
        0,
        null,
        windows.OPEN_EXISTING,
        windows.FILE_FLAG_OVERLAPPED,
        null,
    );
    if (client == windows.INVALID_HANDLE_VALUE) return error.PipeCreationFailed;
    defer _ = windows.CloseHandle(client);

    // Queue a write on the client handle
    const buf: []const u8 = @as([1000]u8, @splat(0xAA))[0..];

    var write_req = Request{
        .handle = client,
        .op_data = .{ .write = buf },
    };
    try context.register(&write_req);
    try context.queue(&write_req);
    try context.submit();

    var write_res: i32 = 0;
    const completed_write = try context.dequeue(&write_res);
    try std.testing.expect(completed_write == &write_req);
    try std.testing.expect(write_res == buf.len);

    // Queue a read on the server handle
    var read_buf: [1002]u8 = undefined;

    var read_req = Request{
        .handle = server,
        .op_data = .{ .read = read_buf[0..] },
    };
    try context.register(&read_req);
    try context.queue(&read_req);
    try context.submit();

    var read_res: i32 = 0;
    const completed_read = try context.dequeue(&read_res);
    try std.testing.expect(completed_read == &read_req);
    try std.testing.expect(read_res == buf.len);

    try std.testing.expectEqualSlices(u8, buf[0..], read_buf[0..@intCast(read_res)]);
}
