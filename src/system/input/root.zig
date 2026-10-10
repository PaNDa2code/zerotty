pub const keyboard = @import("keyboard.zig");
pub const mouse = @import("mouse.zig");

pub const InputEvent = union(enum) {
    keyboard: keyboard.KeyEvent,
    mouse: mouse.MouseEvent,
    utf8_codepoint: u21,

    const std = @import("std");

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try switch (self) {
            .keyboard => |kb| writer.print("keyboard_{s}({})", .{ @tagName(kb.type), kb.code }),
            .mouse => {},
            .utf8_codepoint => |codepoint| writer.print("codepoint(0x{X})", .{codepoint}),
        };
    }
};
