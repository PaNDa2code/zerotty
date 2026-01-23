const std = @import("std");
const clamp = std.math.clamp;
const assert = std.debug.assert;

pub const ansi = struct {
    pub const ColorIndex = enum(u8) {
        // normal colors
        black = 0,
        red = 1,
        green = 2,
        yellow = 3,
        blue = 4,
        magenta = 5,
        cyan = 6,
        white = 7,
        bright_black = 8,
        bright_red = 9,
        bright_green = 10,
        bright_yellow = 11,
        bright_blue = 12,
        bright_magenta = 13,
        bright_cyan = 14,
        bright_white = 15,
        //  16...231 => 6x6x6 color cube
        // 232...255 => 24 shades of grayscale
        _,
    };

    pub const Flags = packed struct(u8) {
        bold: bool = false,
        italic: bool = false,
        underline: bool = false,
        strikethrough: bool = false,
        blink: bool = false,
    };

    pub const ColorState = struct {
        fg: RGBA,
        bg: RGBA,
    };
};

pub const RGBA = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    // zig fmt: off
    pub const red   = rgba(255, 0,  0,  255);
    pub const green = rgba(0,   255,0,  255);
    pub const blue  = rgba(0,   0,  255,255);
    pub const white = rgba(255, 255,255,255);
    pub const black = rgba(0,   0,  0,  255);
    // zig fmt: on

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) RGBA {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn alpha(self: RGBA, a: u8) RGBA {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    pub fn mix(lhs: RGBA, rhs: RGBA, s: f32) RGBA {
        const t = clamp(s, 0.0, 1.0);
        return .{
            .r = lerpu8(lhs.r, rhs.r, t),
            .g = lerpu8(lhs.g, rhs.g, t),
            .b = lerpu8(lhs.b, rhs.b, t),
            .a = lerpu8(lhs.a, rhs.a, t),
        };
    }

    fn lerpu8(a: u8, b: u8, t: f32) u8 {
        const af: f32 = @floatFromInt(a);
        const bf: f32 = @floatFromInt(b);
        return @intFromFloat(@mulAdd(f32, bf - af, t, af));
    }

    pub fn fromInt(value: u32) RGBA {
        return @bitCast(value);
    }

    pub fn toInt(self: RGBA) u32 {
        return @bitCast(self);
    }

    /// convert hex rgb string like `#00eeff` to RGBA
    /// expects string length 7 and '#' at start, else
    /// is undefined behavior
    pub fn fromRGBHexString(color: []const u8) RGBA {
        assert(color.len == 7 and color[0] == '#');

        var int: u32 = 0;

        inline for (color[1..7]) |c| {
            int = (int << 4) | hexToU8(c);
        }

        int = (int << 8) | 0xFF; // set alpha byte

        return RGBA.fromInt(int);
    }

    fn hexToU8(c: u8) u8 {
        return switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => 10 + (c - 'a'),
            'A'...'F' => 10 + (c - 'A'),
            else => unreachable,
        };
    }
};
