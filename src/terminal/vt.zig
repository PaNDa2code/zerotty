const std = @import("std");
const vt = @import("vtparse");
const Terminal = @import("Terminal.zig");
const Emulator = @import("Emulator.zig");
const zerotty = @import("zerotty");
const color = zerotty.terminal.color;
const log = std.log.scoped(.vt);

const Grid = zerotty.terminal.grid.Grid;
pub const EraseMode = Grid.EraseMode;

const CursorMoveAction = union(enum) {
    abs: struct { x: ?u16 = null, y: ?u16 = null },
    relative: struct { dx: i32 = 0, dy: i32 = 0 },
};

const VTColor = union(enum) {
    ansi_index: color.ansi.ColorIndex,
    true_color: color.RGBA,
};

pub const Action = union(enum) {
    print: u21,
    cursor_move: CursorMoveAction,
    erase_display: EraseMode,
    erase_line: EraseMode,
    erase_chars: u16,
    delete_chars: u16,

    change_fg: ?VTColor,
    change_bg: ?VTColor,

    set_attrs: struct { to_set: color.ansi.Flags, on: bool },
    reset_style,

    set_progress: struct {
        state: Emulator.ProgressBarState,
        value: u8,
    },

    set_charset: Emulator.Charset,

    linefeed,
    carriage_return,
    backspace,
    bell,

    pub fn format(
        self: Action,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try switch (self) {
            .print => |cb| writer.print("Action.print({})", .{cb}),
            .cursor_move => |cmv| switch (cmv) {
                .abs => |abs| writer.print("Action.cursor_move.abs({?},{?})", .{ abs.x, abs.y }),
                .relative => |rel| writer.print("Action.cursor_move.relative({},{})", .{ rel.dx, rel.dy }),
            },
            .erase_display => |mode| writer.print("Action.erase_display({})", .{@backingInt(mode)}),
            .erase_line => |mode| writer.print("Action.erase_line({})", .{@backingInt(mode)}),
            .erase_chars => |n| writer.print("Action.erase_chars({})", .{n}),
            .delete_chars => |n| writer.print("Action.delete_chars({})", .{n}),

            .change_fg => |c| writer.print("Action.change_fg({?})", .{c}),
            .change_bg => |c| writer.print("Action.change_bg({?})", .{c}),

            .set_charset => |chr| writer.print("Action.set_charset({s})", .{@tagName(chr)}),

            else => writer.print("Action.{s}", .{@tagName(self)}),
        };
    }
};

// Only SGR can emit more than one, and it emits at most one per parameter.
pub const ActionQueue = zerotty.ds.queue.BoundedQueue(Action, .reset_style, 16);

/// Decodes vt state-machine to `Action`
pub const Decoder = struct {
    osc_buffer: [128]u8 = @splat(0),
    osc_len: usize = 0,

    utf8_buffer: [4]u8 = @splat(0),
    utf8_len: u8 = 0,

    charset: Emulator.Charset = .ascii,
};

pub const Parser = vt.VTParser;

pub fn vtparserEntry(state: *const vt.ParserData, to_action: vt.Action, char: u8, user_data: ?*anyopaque) void {
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));

    var actions: ActionQueue = .{};
    decode(state, to_action, char, &terminal.decoder, &actions);

    while (actions.pop()) |action| {
        log.debug("{f}", .{action});
        apply(terminal, action);
    }
}

/// Turn one vtparse event into zero or more terminal-independent actions.
pub fn decode(
    state: *const vt.ParserData,
    to_action: vt.Action,
    char: u8,
    decoder: *Decoder,
    out: *ActionQueue,
) void {
    switch (to_action) {
        .CSI_DISPATCH => decodeCsi(state, char, out),
        .ESC_DISPATCH => decodeEsc(state, char, out),
        .PRINT => decodePrint(decoder, char, out),
        .OSC_START => decoder.osc_len = 0,
        .OSC_PUT => {
            if (decoder.osc_len < decoder.osc_buffer.len) {
                decoder.osc_buffer[decoder.osc_len] = char;
                decoder.osc_len += 1;
            }
        },
        .OSC_END => decodeOsc(decoder, out),
        .EXECUTE => decodeExecute(state, char, out),
        else => {},
    }
}

/// Apply a decoded action to the terminal.
pub fn apply(terminal: *Terminal, action: Action) void {
    switch (action) {
        .print => |codepoint| putCodepoint(terminal, codepoint),
        .cursor_move => |move| applyCursorMove(terminal, move),
        .erase_display => |mode| terminal.grid.eraseDisplay(terminal.allocator, mode) catch unreachable,
        .erase_line => |mode| terminal.grid.eraseLine(terminal.allocator, @backingInt(mode)) catch unreachable,
        .erase_chars => {}, // ECH is not supported by Grid yet.
        .delete_chars => |n| terminal.grid.deleteChars(terminal.allocator, n) catch unreachable,

        .change_fg => |value| terminal.emulator.current_style.fg_color =
            resolveColor(terminal, value, terminal.emulator.default_style.fg_color),
        .change_bg => |value| terminal.emulator.current_style.bg_color =
            resolveColor(terminal, value, terminal.emulator.default_style.bg_color),

        .set_attrs => |attrs| {
            const flags_info = @typeInfo(color.ansi.Flags).@"struct";
            inline for (flags_info.field_names, flags_info.field_types) |field_name, field_type| {
                if (field_type == bool and @field(attrs.to_set, field_name)) {
                    @field(terminal.emulator.current_style.flags, field_name) = attrs.on;
                }
            }
        },
        .reset_style => terminal.emulator.current_style = terminal.emulator.default_style,

        .set_progress => |progress| {
            terminal.emulator.progress_state = progress.state;
            terminal.emulator.progress = progress.value;
            log.debug("progress: {} {}%", .{ terminal.emulator.progress_state, terminal.emulator.progress });
        },

        .set_charset => |charset| terminal.decoder.charset = charset,

        .linefeed => terminal.grid.linefeed(terminal.allocator) catch unreachable,
        .carriage_return => terminal.grid.carriageReturn(),
        .backspace => backspace(terminal),
        .bell => {
            if (terminal.emulator.bell_action_callback) |callback|
                callback(terminal.emulator.bell_action_data);
        },
    }
}

fn decodeCsi(state: *const vt.ParserData, char: u8, out: *ActionQueue) void {
    switch (char) {
        'm' => decodeSgr(state, out),

        'A' => emitCursorRelative(out, 0, -countParam(state, 0)), // Cursor Up
        'B' => emitCursorRelative(out, 0, countParam(state, 0)), // Cursor Down
        'C' => emitCursorRelative(out, countParam(state, 0), 0), // Cursor Right
        'D' => emitCursorRelative(out, -countParam(state, 0), 0), // Cursor Left

        'H', 'f' => { // Cursor Position
            const row = positionParam(state, 0, 1);
            const col = positionParam(state, 1, 1);
            out.pushAssumeCapacity(.{ .cursor_move = .{ .abs = .{ .x = col, .y = row } } });
        },
        'J' => out.pushAssumeCapacity(.{ .erase_display = eraseMode(paramOr(state, 0, 0)) }), // Erase in Display
        'K' => out.pushAssumeCapacity(.{ .erase_line = eraseMode(paramOr(state, 0, 0)) }), // Erase in Line
        'P' => out.pushAssumeCapacity(.{ .delete_chars = countParamU16(state, 0) }), // DCH — Delete Character(s)

        'h' => {}, // Set Mode (ignore for now)
        'l' => {}, // Reset Mode (ignore for now)
        else => {},
    }
}

fn decodeEsc(state: *const vt.ParserData, char: u8, out: *ActionQueue) void {
    if (state.num_intermediate_chars == 1 and state.intermediate_chars[0] == '(') {
        switch (char) {
            '0' => out.pushAssumeCapacity(.{ .set_charset = .dec_special_graphics }),
            'B' => out.pushAssumeCapacity(.{ .set_charset = .ascii }),
            else => {},
        }
    }
    // '=' (application keypad) and '>' (normal keypad) are ignored for now.
}

fn decodeExecute(state: *const vt.ParserData, char: u8, out: *ActionQueue) void {
    switch (char) {
        0x0A => out.pushAssumeCapacity(.linefeed),
        0x0D => out.pushAssumeCapacity(.carriage_return),
        0x08 => out.pushAssumeCapacity(.backspace),
        0x07 => out.pushAssumeCapacity(.bell),
        0x50 => out.pushAssumeCapacity(.{ .delete_chars = countParamU16(state, 0) }),
        else => {},
    }
}

fn decodeOsc(decoder: *Decoder, out: *ActionQueue) void {
    const payload = decoder.osc_buffer[0..decoder.osc_len];

    if (!std.mem.startsWith(u8, payload, "9;4;")) return;

    const args = payload[4..];
    var it = std.mem.splitScalar(u8, args, ';');

    const state_str = it.next() orelse return;
    const state_int = std.fmt.parseInt(u3, state_str, 10) catch return;

    const progress_state: Emulator.ProgressBarState = switch (state_int) {
        0 => .remove,
        1 => .set,
        2 => .@"error",
        3 => .indeterminate,
        4 => .pause,
        else => return,
    };

    const progress_str = it.next() orelse "0";
    const progress_int = std.fmt.parseInt(u32, progress_str, 10) catch return;

    out.pushAssumeCapacity(.{ .set_progress = .{
        .state = progress_state,
        .value = @intCast(@min(progress_int, 100)),
    } });
}

fn decodeSgr(state: *const vt.ParserData, out: *ActionQueue) void {
    // No params = reset
    if (state.num_params == 0) {
        out.pushAssumeCapacity(.reset_style);
        return;
    }

    var i: usize = 0;

    while (i < state.num_params) : (i += 1) {
        const p = state.params[i];

        switch (p) {
            0 => out.pushAssumeCapacity(.reset_style),

            1 => emitAttr(out, .{ .bold = true }, true),
            4 => emitAttr(out, .{ .underline = true }, true),
            5, 6 => emitAttr(out, .{ .blink = true }, true),
            7 => emitAttr(out, .{ .inverse = true }, true),
            9 => emitAttr(out, .{ .strikethrough = true }, true),

            22 => emitAttr(out, .{ .bold = false }, false),
            23 => emitAttr(out, .{ .italic = false }, false),
            24 => emitAttr(out, .{ .underline = false }, false),
            25 => emitAttr(out, .{ .blink = false }, false),
            27 => emitAttr(out, .{ .inverse = false }, false),
            29 => emitAttr(out, .{ .strikethrough = false }, false),

            30...37, 90...97 => {
                const is_bright = p >= 90;
                const base: u8 = if (is_bright) 90 else 30;
                const offset: u8 = if (is_bright) 8 else 0;
                const idx: u8 = @intCast((p - base) + offset);

                out.pushAssumeCapacity(.{ .change_fg = .{ .ansi_index = @fromBackingInt(idx) } });
            },
            40...47, 100...107 => {
                const is_bright = p >= 100;
                const base: u8 = if (is_bright) 100 else 40;
                const offset: u8 = if (is_bright) 8 else 0;
                const idx: u8 = @intCast((p - base) + offset);

                out.pushAssumeCapacity(.{ .change_bg = .{ .ansi_index = @fromBackingInt(idx) } });
            },

            38, 48 => {
                // 256-color: 38;5;N / 48;5;N
                if (i + 2 < state.num_params and
                    state.params[i + 1] == 5 and
                    state.params[i + 2] < 256)
                {
                    const idx: u8 = @intCast(state.params[i + 2]);
                    const value: VTColor = .{ .ansi_index = @fromBackingInt(idx) };

                    if (p == 38)
                        out.pushAssumeCapacity(.{ .change_fg = value })
                    else
                        out.pushAssumeCapacity(.{ .change_bg = value });

                    i += 2;
                }
                // Truecolor: 38;2;R;G;B / 48;2;R;G;B
                else if (i + 4 < state.num_params and state.params[i + 1] == 2) {
                    const r: u8 = @intCast(@min(state.params[i + 2], 255));
                    const g: u8 = @intCast(@min(state.params[i + 3], 255));
                    const b: u8 = @intCast(@min(state.params[i + 4], 255));
                    const value: VTColor = .{ .true_color = .rgba(r, g, b, 255) };

                    if (p == 38)
                        out.pushAssumeCapacity(.{ .change_fg = value })
                    else
                        out.pushAssumeCapacity(.{ .change_bg = value });

                    i += 4;
                }
            },

            39 => out.pushAssumeCapacity(.{ .change_fg = null }),
            49 => out.pushAssumeCapacity(.{ .change_bg = null }),

            else => {},
        }
    }
}

fn decodePrint(decoder: *Decoder, char: u8, out: *ActionQueue) void {
    if (char < 0x80) {
        flushUtf8(decoder, out);
        out.pushAssumeCapacity(.{ .print = translate(decoder.charset, char) });
        return;
    }

    if (decoder.utf8_len == 0) {
        const expected = std.unicode.utf8ByteSequenceLength(char) catch 1;

        decoder.utf8_buffer[0] = char;
        decoder.utf8_len = 1;

        if (decoder.utf8_len >= expected)
            flushUtf8(decoder, out);
    } else {
        const expected = std.unicode.utf8ByteSequenceLength(decoder.utf8_buffer[0]) catch {
            out.pushAssumeCapacity(.{ .print = 0xFFFD }); // stray continuation / invalid lead
            decoder.utf8_len = 0;
            return;
        };

        decoder.utf8_buffer[decoder.utf8_len] = char;
        decoder.utf8_len += 1;

        if (decoder.utf8_len >= expected)
            flushUtf8(decoder, out);
    }
}

/// Decode the buffered bytes and emit one print action. A truncated sequence
/// at the end of the stream (or a control char interrupting it) becomes U+FFFD.
fn flushUtf8(decoder: *Decoder, out: *ActionQueue) void {
    if (decoder.utf8_len == 0) return;

    const expected = std.unicode.utf8ByteSequenceLength(decoder.utf8_buffer[0]) catch 0;
    var codepoint: u21 = 0xFFFD;

    if (decoder.utf8_len == expected)
        codepoint = std.unicode.utf8Decode(decoder.utf8_buffer[0..expected]) catch 0xFFFD;

    decoder.utf8_len = 0;
    out.pushAssumeCapacity(.{ .print = codepoint });
}

const dec_special_graphics_table = [32]u21{
    0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0,
    0x00B1, 0x2424, 0x240B, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C,
    0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534,
    0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7,
};

fn translate(charset: Emulator.Charset, byte: u8) u21 {
    if (charset == .dec_special_graphics and byte >= 0x5F and byte <= 0x7E) {
        return dec_special_graphics_table[byte - 0x5F];
    } else {
        @branchHint(.likely);
        return @intCast(byte);
    }
}

fn emitAttr(out: *ActionQueue, to_set: color.ansi.Flags, on: bool) void {
    out.pushAssumeCapacity(.{ .set_attrs = .{ .to_set = to_set, .on = on } });
}

fn emitCursorRelative(out: *ActionQueue, dx: i32, dy: i32) void {
    out.pushAssumeCapacity(.{ .cursor_move = .{ .relative = .{ .dx = dx, .dy = dy } } });
}

fn hasParam(state: *const vt.ParserData, index: usize) bool {
    return index < @as(usize, state.num_params);
}

fn paramOr(state: *const vt.ParserData, index: usize, default: u32) u32 {
    return if (hasParam(state, index)) state.params[index] else default;
}

/// Movement counts treat an explicit 0 as 1.
fn countParam(state: *const vt.ParserData, index: usize) i32 {
    const value = @max(paramOr(state, index, 1), 1);
    return @intCast(@min(value, std.math.maxInt(i32)));
}

fn countParamU16(state: *const vt.ParserData, index: usize) u16 {
    const value = @max(paramOr(state, index, 1), 1);
    return @intCast(@min(value, std.math.maxInt(u16)));
}

fn positionParam(state: *const vt.ParserData, index: usize, default: u32) u16 {
    return @intCast(@min(paramOr(state, index, default), std.math.maxInt(u16)));
}

fn eraseMode(value: u32) EraseMode {
    return @fromBackingInt(@intCast(@as(usize, value)));
}

fn applyCursorMove(terminal: *Terminal, move: CursorMoveAction) void {
    terminal.grid.clearWrapPending();

    switch (move) {
        .abs => |abs| {
            if (abs.y) |row|
                terminal.grid.cursor_y = @min(@as(usize, row) -| 1, terminal.grid.visable_rows -| 1);
            if (abs.x) |col|
                terminal.grid.cursor_x = @min(@as(usize, col) -| 1, terminal.grid.rows_width -| 1);
        },
        .relative => |rel| {
            const max_x: i32 = @intCast(terminal.grid.rows_width -| 1);
            const max_y: i32 = @intCast(terminal.grid.visable_rows -| 1);

            const x = @as(i32, @intCast(terminal.grid.cursor_x)) + rel.dx;
            const y = @as(i32, @intCast(terminal.grid.cursor_y)) + rel.dy;

            terminal.grid.cursor_x = @intCast(std.math.clamp(x, 0, max_x));
            terminal.grid.cursor_y = @intCast(std.math.clamp(y, 0, max_y));
        },
    }
}

fn resolveColor(terminal: *Terminal, value: ?VTColor, default: color.RGBA) color.RGBA {
    const resolved = value orelse return default;

    return switch (resolved) {
        .ansi_index => |index| terminal.emulator.color_palette.get(index),
        .true_color => |rgba| rgba,
    };
}

fn putCodepoint(terminal: *Terminal, codepoint: u21) void {
    terminal.grid.putChar(terminal.allocator, .{
        .fg_color = terminal.emulator.current_style.fg_color,
        .bg_color = terminal.emulator.current_style.bg_color,
        .flags = terminal.emulator.current_style.flags,
        .unicode = codepoint,
    }) catch unreachable;
}

fn backspace(terminal: *Terminal) void {
    terminal.grid.clearWrapPending();
    if (terminal.grid.cursor_x > 0)
        terminal.grid.cursor_x -= 1;
}
