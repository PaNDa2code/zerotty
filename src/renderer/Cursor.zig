const Cursor = @This();

pub const Style = enum(u8) {
    block = 0,
    bar = 1,
    underline = 2,
};

pub const DEFAULT_STYLE = Style.block;
pub const DEFAULT_BLINK = true;

row: u32,
col: u32,

style: Style,
blink: bool,

visable: bool,

blink_intervals: u64,
blink_toggle: bool,

timer: std.time.Timer,

row_len: u32,

pub fn init() !Cursor {
    return .{
        .row = 0,
        .col = 0,
        .style = .block,
        .blink = true,
        .visable = true,
        .blink_toggle = true,
        .blink_intervals = std.time.ns_per_s,
        .timer = try .start(),
        .row_len = 0,
    };
}

pub fn setCSICode(self: *Cursor, code: u8) !void {
    if (code == 0) {
        self.style = DEFAULT_STYLE;
        self.blink = DEFAULT_BLINK;
        return;
    }

    self.blink = (code & 0x01) == 1;

    const style_code = (code - 1) >> 1;

    if (style_code > 2)
        return error.UndefinedCSICursor;

    self.style = @enumFromInt(style_code);
}

pub fn setPos(self: *Cursor, row: u32, col: u32) void {
    self.row = row;
    self.col = col;
}

pub fn setRow(self: *Cursor, row: u32) void {
    self.row = row;
}

pub fn setCol(self: *Cursor, col: u32) void {
    self.col = col;
}

pub fn nextCol(self: *Cursor) void {
    self.col += 1;
    if (self.col >= self.row_len) {
        self.col -= self.row_len;
        self.row += 1;
    }
}

pub fn showCursor(self: *Cursor) bool {
    if (!self.visable)
        return false;

    if (!self.blink)
        return true;

    if (self.timer.read() >= self.toggle_intervals) {
        self.timer.reset();
        self.toggle = !self.toggle;
    }

    return self.toggle;
}

const std = @import("std");
