//! A Circular Buffer implementation using double-mapped virtual memory.
//!
//! This data structure maps the same physical memory region to two adjacent virtual addresses.
//! This allows read/write operations that wrap around the buffer boundary to be handled
//! as contiguous memory operations, eliminating the need for split `memcpy` calls or
//! complex boundary logic.
//!
//! # Memory Layout
//!
//!     VIRTUAL MEMORY (What the program sees)
//!     +---------------------------+---------------------------+
//!     |         VIEW 1            |         VIEW 2            |
//!     |      [0 ... N-1]          |      [N ... 2N-1]         |
//!     +---------------------------+---------------------------+
//!                   |                           |
//!                   |     (Map 1)               | (Map 2)
//!           +-------+                           |
//!           |                                   |
//!           |+----------------------------------+
//!           ||
//!           vv
//!           +---------------------------+
//!           |     PHYSICAL MEMORY       |
//!           |      (Actual RAM)         |
//!           +---------------------------+
//!
const CircularBuffer = @This();

pub const page_size = std.heap.pageSize();

single_map_size: usize = 0,
full_view: []align(page_size) u8 = undefined,

start: usize,
len: usize,

pub const CreateError = error{
    VMemoryReserveFailed,
    VMemorySplitingFailed,
    VMemoryMappingFailed,
    CreatingPageMappingFailed,
    PageMappingFailed,
};

pub fn new(requsted_size: usize) !CircularBuffer {
    var self = CircularBuffer{};
    try self.init(if (requsted_size == 0) 1 else requsted_size);
    return self;
}

pub fn init(self: *CircularBuffer, requsted_size: usize) CreateError!void {
    return switch (builtin.os.tag) {
        .windows => self.initWindows(requsted_size),
        .linux, .macos => self.initPosix(requsted_size),
        else => @compileError("Target os is not supported"),
    };
}

pub fn deinit(self: *CircularBuffer) void {
    return switch (builtin.os.tag) {
        .windows => self.deinitWindows(),
        .linux, .macos => self.deinitPosix(),
        else => @compileError("Target os is not supported"),
    };
}

fn initWindows(self: *CircularBuffer, requsted_size: usize) CreateError!void {
    const size = std.mem.alignForward(usize, requsted_size, page_size);

    const palce_holder = win32.system.memory.VirtualAlloc2(
        null,
        null,
        size * 2,
        .{ .RESERVE = 1, .RESERVE_PLACEHOLDER = 1 },
        @bitCast(win32.system.memory.PAGE_NOACCESS),
        null,
        0,
    );

    if (palce_holder == null) {
        return CreateError.VMemoryReserveFailed;
    }

    const flags: u32 = @intFromEnum(win32.system.memory.MEM_PRESERVE_PLACEHOLDER) | @intFromEnum(win32.system.memory.MEM_RELEASE);

    if (std.os.windows.kernel32.VirtualFree(palce_holder, size, flags) == 0) {
        return CreateError.VMemorySplitingFailed;
    }

    const section = win32.system.memory.CreateFileMappingW(
        win32.foundation.INVALID_HANDLE_VALUE,
        null,
        .{ .PAGE_READWRITE = 1 },
        0,
        @intCast(size),
        null,
    );

    if (section == null or section == win32.foundation.INVALID_HANDLE_VALUE) {
        return CreateError.CreatingPageMappingFailed;
    }

    defer _ = win32.foundation.CloseHandle(section);

    const view1 = win32.system.memory.MapViewOfFile3(
        section,
        null,
        palce_holder,
        0,
        size,
        .{ .REPLACE_PLACEHOLDER = 1 },
        @bitCast(win32.system.memory.PAGE_READWRITE),
        null,
        0,
    );

    if (view1 == null) {
        return CreateError.VMemoryMappingFailed;
    }

    errdefer _ = win32.system.memory.UnmapViewOfFile(view1);

    const view2 = win32.system.memory.MapViewOfFile3(
        section,
        null,
        @ptrFromInt(@intFromPtr(palce_holder) + size),
        0,
        size,
        .{ .REPLACE_PLACEHOLDER = 1 },
        @bitCast(win32.system.memory.PAGE_READWRITE),
        null,
        0,
    );

    if (view2 == null) {
        return CreateError.VMemoryMappingFailed;
    }

    errdefer _ = win32.system.memory.UnmapViewOfFile(view2);

    self.full_view.ptr = @ptrCast(@alignCast(view1.?));
    self.full_view.len = size * 2;
    self.single_map_size = size;
}

fn initPosix(self: *CircularBuffer, requsted_size: usize) CreateError!void {
    const size = std.mem.alignForward(usize, requsted_size, page_size);

    const place_holder = std.posix.mmap(
        null,
        size * 2,
        std.posix.PROT.NONE,
        .{ .ANONYMOUS = true, .TYPE = .PRIVATE },
        -1,
        0,
    ) catch {
        return CreateError.VMemoryReserveFailed;
    };

    errdefer std.posix.munmap(place_holder);

    const split_address: []u8 align(page_size) = place_holder[size..];
    std.posix.munmap(@alignCast(split_address));

    // using shm_open to work with both linux and macos
    const fd = std.c.shm_open("/ciruler_buffer_file", 2 | 64, 0x180);
    if (fd == -1) return CreateError.CreatingPageMappingFailed;
    defer _ = std.c.shm_unlink("/ciruler_buffer_file");

    _ = std.posix.ftruncate(fd, size) catch {
        return CreateError.CreatingPageMappingFailed;
    };

    const view1 = std.posix.mmap(
        @alignCast(place_holder.ptr),
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .FIXED = true },
        fd,
        0,
    ) catch {
        return CreateError.VMemoryMappingFailed;
    };

    errdefer std.posix.munmap(view1);

    const view2 = std.posix.mmap(
        @alignCast(place_holder.ptr + size),
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .FIXED = true },
        fd,
        0,
    ) catch {
        return CreateError.VMemoryMappingFailed;
    };

    errdefer std.posix.munmap(view2);

    self.full_view = view1.ptr[0 .. size * 2];
    self.single_map_size = size;
}

fn deinitPosix(self: *CircularBuffer) void {
    if (self.full_view.len == 0 or self.single_map_size == 0) return;
    std.posix.munmap(@alignCast(self.full_view[0..self.single_map_size]));
    std.posix.munmap(@alignCast(self.full_view[self.single_map_size..]));
    self.full_view = &[_]u8{};
    self.single_map_size = 0;
}

fn deinitWindows(self: *CircularBuffer) void {
    if (self.full_view.len == 0 or self.single_map_size == 0) return;
    _ = win32.system.memory.UnmapViewOfFile(self.full_view.ptr);
    _ = win32.system.memory.UnmapViewOfFile(self.full_view[self.single_map_size..].ptr);
}

fn writeCommit(self: *CircularBuffer, bytes_count: usize) void {
    self.len += bytes_count;
    if (self.len > self.single_map_size) {
        self.start = self.len - self.single_map_size;
        self.len = self.single_map_size;
    }
}

pub fn write(self: *CircularBuffer, buffer: []const u8) usize {
    const bytes = @min(self.single_map_size, buffer.len);
    const write_start = self.start + self.len;
    const write_end = write_start + bytes;
    @memcpy(self.full_view[write_start..write_end], buffer[0..bytes]);
    self.writeCommit(bytes);
    return bytes;
}

pub fn read(self: *CircularBuffer, buffer: []u8) usize {
    const bytes = @min(self.len, buffer.len);
    @memcpy(buffer[0..bytes], self.full_view[self.start..]);
    return bytes;
}

pub fn getReadableSlice(self: *const CircularBuffer) []const u8 {
    return self.full_view[self.start..][0..self.len];
}

test CircularBuffer {}

const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");
