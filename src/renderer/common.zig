pub const ColorRGBAf32 = packed struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    pub const Red = ColorRGBAf32{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const Green = ColorRGBAf32{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const Blue = ColorRGBAf32{ .r = 0, .g = 0, .b = 1, .a = 1 };
    pub const White = ColorRGBAf32{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const Black = ColorRGBAf32{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const Gray = ColorRGBAf32{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 0.75 };

    pub fn toU8(self: ColorRGBAf32) ColorRGBAu8 {
        const p = 255;
        return .{
            .r = @as(u8, @intFromFloat(self.r)) * p,
            .g = @as(u8, @intFromFloat(self.g)) * p,
            .b = @as(u8, @intFromFloat(self.b)) * p,
            .a = @as(u8, @intFromFloat(self.a)) * p,
        };
    }
};

pub const ColorRGBAu8 = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    pub const Red = ColorRGBAu8{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const Green = ColorRGBAu8{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const Blue = ColorRGBAu8{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const White = ColorRGBAu8{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const Black = ColorRGBAu8{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const Gray = ColorRGBAu8{ .r = 76, .g = 76, .b = 76, .a = 191 };

    pub fn toF32(self: ColorRGBAu8) ColorRGBAf32 {
        const p = 1 / 255;
        return .{
            .r = @as(f32, @floatFromInt(self.r)) * p,
            .g = @as(f32, @floatFromInt(self.g)) * p,
            .b = @as(f32, @floatFromInt(self.b)) * p,
            .a = @as(f32, @floatFromInt(self.a)) * p,
        };
    }
};
