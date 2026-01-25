pub const Keyboard = @import("Keyboard.zig");
pub const Xkb = @import("Xkb.zig");

pub const UTF8CodePoint = enum(u21) {
    null_char = 0,
    _,

    pub fn toInt(codepoint: UTF8CodePoint) u21 {
        return @intFromEnum(codepoint);
    }
};

pub const Modifiers = packed struct {
    ctrl: bool = false,
    shift: bool = false,
    alt: bool = false,
    super: bool = false,
};
