pub const keyboard = @import("keyboard.zig");
pub const mouse = @import("mouse.zig");

pub const InputEvent = union(enum) {
    keyboard: keyboard.KeyEvent,
    mouse: mouse.MouseEvent,
    utf8_codepoint: u21,
};
