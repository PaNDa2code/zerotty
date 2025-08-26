pub const ColorRGBA = packed struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    pub const Red = ColorRGBA{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const Green = ColorRGBA{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const Blue = ColorRGBA{ .r = 0, .g = 0, .b = 1, .a = 1 };
    pub const White = ColorRGBA{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const Black = ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const Gray = ColorRGBA{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 0.75 };
};
