pub const ColorRGBAu8 = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) ColorRGBAu8 {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn alpha(self: ColorRGBAu8, a: u8) ColorRGBAu8 {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    // zig fmt: off
    pub const Red   = rgba(255, 0,  0,  255);
    pub const Green = rgba(0,   255,0,  255);
    pub const Blue  = rgba(0,   0,  255,255);
    pub const White = rgba(255, 255,255,255);
    pub const Black = rgba(0,   0,  0,  255);
    // zig fmt: on

    pub fn fromInt(value: u32) ColorRGBAu8 {
        return @bitCast(value);
    }

    pub fn toInt(self: ColorRGBAu8) u32 {
        return @bitCast(self);
    }

    pub fn toF32(self: ColorRGBAu8) ColorRGBAf32 {
        const p = 1.0 / 255.0;
        return .{
            .r = @as(f32, @floatFromInt(self.r)) * p,
            .g = @as(f32, @floatFromInt(self.g)) * p,
            .b = @as(f32, @floatFromInt(self.b)) * p,
            .a = @as(f32, @floatFromInt(self.a)) * p,
        };
    }
};

pub const ColorRGBAf32 = packed struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) ColorRGBAf32 {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub const Red = ColorRGBAu8.Red.toF32();
    pub const Green = ColorRGBAu8.Green.toF32();
    pub const Blue = ColorRGBAu8.Blue.toF32();
    pub const White = ColorRGBAu8.White.toF32();
    pub const Black = ColorRGBAu8.Black.toF32();

    pub fn toU8(self: ColorRGBAf32) ColorRGBAu8 {
        return .{
            .r = @as(u8, @intFromFloat(self.r * 255.0)),
            .g = @as(u8, @intFromFloat(self.g * 255.0)),
            .b = @as(u8, @intFromFloat(self.b * 255.0)),
            .a = @as(u8, @intFromFloat(self.a * 255.0)),
        };
    }
};
