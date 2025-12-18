const Scrollback = @This();

const std = @import("std");

pub const LineFlags = packed struct(u8) {
    double_width: bool = false,
    double_height_top: bool = false,
    double_height_bot: bool = false,
    has_images: bool = false,
    hard_wrapped: bool = false,
    prompt: bool = false,

    _padding: u2 = 0,
};

pub const LogicalLine = struct {
    codepoints: std.ArrayList(u32) = .empty,
    flags: LineFlags = .{},
    images_count: usize = 0,
};

const max_line_len = 1024 * 16;

lines: std.MultiArrayList(LogicalLine),
head: usize,
viewport_offset: usize,

pub fn init(allocator: std.mem.Allocator, max_lines: usize) !Scrollback {
    var lines = std.MultiArrayList(LogicalLine){};
    try lines.ensureTotalCapacity(allocator, max_lines);

    @memset(lines.items(.codepoints), .{});

    return .{
        .lines = lines,
        .head = 0,
        .viewport_offset = 0,
    };
}

pub fn deinit(self: *Scrollback, allocator: std.mem.Allocator) void {
    for (self.lines.items(.codepoints)) |*arr| {
        arr.deinit(allocator);
    }
    self.lines.deinit(allocator);
}

pub fn addLine(self: *Scrollback, line: LogicalLine) void {
    if (self.lines.capacity == self.lines.len) {
        const index = self.head;
        self.head += 1;
        self.lines.set(index, line);
    } else {
        self.lines.appendAssumeCapacity(line);
    }
}

pub fn addCodepoint(self: *Scrollback, allocator: std.mem.Allocator, codepoint: u32) !void {
    const current =
        if (self.head == 0)
            @max(self.lines.len, 1) - 1
        else
            ((self.lines.len + self.head) & (self.lines.capacity - 1)) - 1;

    if (self.lines.len == 0)
        self.addLine(.{});

    try self.lines.items(.codepoints)[current].append(allocator, codepoint);
}

pub fn addLineBreak(self: *Scrollback) void {
    self.addLine(.{});
}
