const std = @import("std");
const clamp = std.math.clamp;
const assert = std.debug.assert;

pub const ansi = struct {
    pub const Palette = struct {
        colors: [256]RGBA,

        pub fn get(self: *const Palette, index: ColorIndex) RGBA {
            return self.colors[@intFromEnum(index)];
        }

        pub fn set(self: *Palette, index: ColorIndex, color: RGBA) void {
            self.colors[@intFromEnum(index)] = color;
        }

        fn defaultPalette() Palette {
            var palette: Palette = undefined;
            for (0..256) |i| {
                const color_index: ColorIndex = @enumFromInt(i);
                palette.set(color_index, colorIndexToRGBA(color_index));
            }
            return palette;
        }

        pub const default = defaultPalette();
    };

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
        _padding: u3 = 0,
    };

    pub const ColorState = struct {
        fg: RGBA,
        bg: RGBA,
    };

    /// returns the default ansi color value
    pub fn colorIndexToRGBA(color_index: ColorIndex) RGBA {
        // zig fmt: off
        return switch (color_index) {
            // Normal colors (0–7)
            .black          => .black,
            .red            => .rgba(205,   0,   0, 255),
            .green          => .rgba(  0, 205,   0, 255),
            .yellow         => .rgba(205, 205,   0, 255),
            .blue           => .rgba(  0,   0, 205, 255),
            .magenta        => .rgba(205,   0, 205, 255),
            .cyan           => .rgba(  0, 205, 205, 255),
            .white          => .rgba(229, 229, 229, 255),

            // Bright colors (8–15)
            .bright_black   => .rgba(127, 127, 127, 255),
            .bright_red     => .red,
            .bright_green   => .green,
            .bright_yellow  => .rgba(255, 255,   0, 255),
            .bright_blue    => .blue,
            .bright_magenta => .rgba(255,   0, 255, 255),
            .bright_cyan    => .rgba(  0, 255, 255, 255),
            .bright_white   => .white,

            _ => blk: {
                const index = @intFromEnum(color_index);

                if (index >= 16 and index <= 231) {
                    const base = index - 16;
                    const r = @divFloor(base, 36);
                    const g = @divFloor(base % 36, 6);
                    const b = base % 6;

                    const scale = [_]u8{ 0, 95, 135, 175, 215, 255 };
                    break :blk RGBA.rgba(scale[r], scale[g], scale[b], 255);
                } else if (index >= 232 and index <= 255) {
                    const gray = 8 + (index - 232) * 10;
                    break :blk RGBA.rgba(gray, gray, gray, 255);
                } else {
                    break :blk RGBA.rgba(0, 0, 0, 255);
                }
            },
        };
    }
    // zig fmt: on
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
        return @bitCast(lerpVec(lhs.getVec(), rhs.getVec(), t));
    }

    fn lerpVec(a: @Vector(4, u8), b: @Vector(4, u8), t: f32) @Vector(4, u8) {
        const af: @Vector(4, f32) = @floatFromInt(a);
        const bf: @Vector(4, f32) = @floatFromInt(b);
        return @intFromFloat(@mulAdd(@Vector(4, f32), bf - af, @splat(t), af));
    }

    fn getVec(self: RGBA) @Vector(4, u8) {
        return @bitCast(self);
    }

    pub fn fromInt(value: u32) RGBA {
        return @bitCast(value);
    }

    pub fn toInt(self: RGBA) u32 {
        return @bitCast(self);
    }

    pub fn floatArray(self: RGBA) [4]f32 {
        const m: @Vector(4, f32) = @splat(1.0 / 255.0);
        const vec: @Vector(4, f32) = @floatFromInt(self.getVec());
        return @bitCast(vec * m);
    }

    /// convert hex rgb string like `#00eeff` to RGBA
    /// expects string length 7 and '#' at start, else
    /// is undefined behavior
    pub fn fromRGBHexString(color: []const u8) RGBA {
        assert(color.len == 7 and color[0] == '#');

        var int: u32 = 0xFF << 24;

        inline for (color[1..7]) |c| {
            int <<= 4;
            int |= (@as(u32, c) & 0xF) + (@as(u32, c) >> 6) * 9;
        }

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
