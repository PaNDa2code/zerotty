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
            .mouse => |ms| switch (ms) {
                .move => |mv| writer.print("mouse_move({:.2},{:.2},{:.2},{:.2})", .{ mv.x, mv.y, mv.dx, mv.dy }),
                .button => |mb| writer.print("mouse_button_{s}({})", .{ @tagName(mb.state), mb.button }),
                .scroll => |sc| writer.print("mouse_scroll({:.2},{:.2})", .{ sc.x_offset, sc.y_offset }),
            },
            .utf8_codepoint => |codepoint| writer.print("codepoint(0x{X})", .{codepoint}),
        };
    }
};
