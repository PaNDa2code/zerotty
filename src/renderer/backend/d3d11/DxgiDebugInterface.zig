const std = @import("std");

const win32 = @import("win32");
const foundation = win32.foundation;
const d3d11 = win32.graphics.direct3d11;
const dxgi = win32.graphics.dxgi;

const IDXGIInfoQueue = dxgi.IDXGIInfoQueue;
const IDXGIDevice = dxgi.IDXGIDevice;
const ID3D11Device = d3d11.ID3D11Device;

const HresultDebugInfo = @import("../../debug/HresultDebugInfo.zig");
const checkHresult = HresultDebugInfo.checkHresult;

const DxgiDebugInterface = @This();

base: HresultDebugInfo,
info_queue: *IDXGIInfoQueue,
next: u64,

pub fn init(device: *IDXGIDevice) !DxgiDebugInterface {
    _ = device;
    var info_queue: *IDXGIInfoQueue = undefined;

    try checkHresult(
        dxgi.DXGIGetDebugInterface1(0, dxgi.IID_IDXGIInfoQueue, @ptrCast(&info_queue)),
    );

    return .{
        .base = undefined,
        .info_queue = info_queue,
        .next = 0,
    };
}

pub fn deinit(self: *const DxgiDebugInterface) void {
    _ = self.info_queue.IUnknown.Release();
}

pub fn set(self: *DxgiDebugInterface) void {
    self.next = self.info_queue.GetNumStoredMessages(dxgi.DXGI_DEBUG_ALL);
}

pub fn writeMessages(self: *const DxgiDebugInterface, writer: std.io.AnyWriter) !void {
    var message_len: usize = 0;
    var buffer: [1024]u8 align(8) = undefined;
    const message: *dxgi.DXGI_INFO_QUEUE_MESSAGE = @ptrCast(&buffer);

    try writer.writeAll("DXGI Messages:\n");
    const messages_count = self.info_queue.GetNumStoredMessages(dxgi.DXGI_DEBUG_ALL);
    for (self.next..messages_count) |i| {
        try checkHresult(
            self.info_queue.GetMessage(dxgi.DXGI_DEBUG_ALL, i, null, &message_len),
        );

        if (message_len > buffer.len)
            return error.DXGIDebugMessageTooBig;

        try checkHresult(
            self.info_queue.GetMessage(dxgi.DXGI_DEBUG_ALL, i, message, &message_len),
        );

        const p_description: [*]const u8 = @ptrCast(message.pDescription);
        try writer.print("{d}: {s}", .{ i - self.next, p_description[0..message.DescriptionByteLength] });
    }
}

pub fn dump(self: *const DxgiDebugInterface) !void {
    const stderr = std.io.getStdErr().writer().any();
    try self.base.what(stderr);
    try self.writeMessages(stderr);
}

pub fn messageBox(self: *const DxgiDebugInterface) void {
    var buffer: [1024 * 6]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    const writer = stream.writer().any();
    self.base.what(writer) catch {};
    self.writeMessages(writer) catch {};
    writer.writeByte(0) catch {};
    buffer[buffer.len - 1] = 0;
    _ = win32.ui.windows_and_messaging.MessageBoxA(null, @ptrCast(&buffer), "hresult error", .{ .ICONHAND = 1 });
}

pub fn DxgiCheckHresult(self: *DxgiDebugInterface, hresult: i32) !void {
    if (hresult >= 0) {
        self.set();
        return;
    }

    self.base = HresultDebugInfo.create(hresult, 2);
    self.messageBox();

    return error.DxgiHresultError;
}
