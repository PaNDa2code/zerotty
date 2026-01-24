const Scrollback = @This();

const std = @import("std");

pub const Range = struct {
    from: usize,
    to: usize,
};

pub const FontStyle = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
};

pub const Style = struct {
    fg_color: @Vector(4, u8) = .{ 255, 255, 255, 255 },
    bg_color: @Vector(4, u8) = .{ 0, 0, 0, 255 },
    font_style: FontStyle,
};

// Logical line
pub const Line = struct {
    utf8: []u8 = &.{},
    ranges: []Range = &.{},
    styles: []Style = &.{},
};

allocator: std.mem.Allocator,

max_lines: usize = 10_000,

bytes_pool: std.ArrayList(u8) = .empty,
lines: Line = .empty,

head: usize = 0,

pub fn init(allocator: std.mem.Allocator) void {
    return .{
        .allocator = allocator,
    };
}

// pub fn pushData(self: *Scrollback, utf8: []const u8) !void {}
//
// pub fn newLine(self: *Scrollback) !void {}
//
// pub fn setStyle(self: *Scrollback, style: Style) !void {}
//
// pub fn setFgColor(self: *Scrollback, color: @Vector(4, u8)) !void {}
//
// pub fn setBgColor(self: *Scrollback, color: @Vector(4, u8)) !void {}
//
// pub fn setFontStyle(self: *Scrollback, style: FontStyle) !void {}
