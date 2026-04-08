const Font = @This();

pub const Face = @import("Face.zig");

ttf: TrueType,
faces: []Face,

scale_x: f32,
scale_y: f32,

pub fn init(
    ttf_buffer: []const u8,
    height: u8,
    width: u8,
) !Font {
    _ = width;
    const ttf = try TrueType.load(ttf_buffer);

    // const scale_x = ttf.scaleForPixelHeight(@floatFromInt(width));
    const scale_y = ttf.scaleForPixelHeight(@floatFromInt(height));

    return .{
        .ttf = ttf,
        .faces = &.{},
        .scale_x = scale_y,
        .scale_y = scale_y,
    };
}

pub fn deinit(self: *const Font) void {
    _ = self;
}

pub fn face(self: *const Font, style: Face.Style) Face {
    _ = style;
    return .{
        .font = self,
        .style = .{},
    };
}

const TrueType = @import("TrueType");
