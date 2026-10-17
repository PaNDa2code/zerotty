const Emulator = @This();

const std = @import("std");
const zerotty = @import("zerotty");
const color = zerotty.terminal.color;

pub const Charset = enum { ascii, dec_special_graphics };

pub const ProgressBarState = enum(u3) {
    remove = 0,
    set = 1,
    @"error" = 2,
    indeterminate = 3,
    pause = 4,
};

pub const Style = struct {
    fg_color: color.RGBA,
    bg_color: color.RGBA,
    flags: color.ansi.Flags = .{},

    pub fn format(
        style: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("fg = {f}, bg = {f}", .{ style.fg_color, style.bg_color });

        const flags_info = @typeInfo(color.ansi.Flags).@"struct";
        inline for (flags_info.field_names, 0..) |field_name, i| {
            if (flags_info.field_types[i] == bool and @field(style.flags, field_name)) {
                try writer.print(", {s}", .{field_name});
            }
        }
    }
};

/// progress bar value from 0-100
progress: u32 = 0,
/// progress bar state
progress_state: ProgressBarState = .remove,

bell_action_callback: ?*const fn (?*anyopaque) void = null,
bell_action_data: ?*anyopaque = null,

ocs_buffer: [128]u8 = @splat(0),
ocs_buffer_len: usize = 0,

/// Partial UTF-8 sequence, since PRINT hands us one byte at a time but cells
/// hold whole codepoints (box drawing, CJK, emoji are 2-4 bytes).
utf8_buf: [4]u8 = undefined,
utf8_len: u8 = 0,
charset: Charset = .ascii,

color_palette: color.ansi.Palette = .default,

default_style: Style,
current_style: Style,
