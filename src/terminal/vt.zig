const std = @import("std");
const vt = @import("vtparse");
const Terminal = @import("Terminal.zig");
const Emulator = @import("Emulator.zig");
const zerotty = @import("zerotty");
const color = zerotty.terminal.color;
const log = std.log.scoped(.vt);

pub const Parser = vt.VTParser;

pub fn vtparserEntry(state: *const vt.ParserData, to_action: vt.Action, char: u8, user_data: ?*anyopaque) void {
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));

    // Any control sequence interrupts a partial UTF-8 sequence; don't let a
    // stray lead byte bleed into the next cell.
    if (to_action == .EXECUTE and char & 0xC0 == 0x80 and
        terminal.emulator.utf8_len > 0)
    {
        printByte(terminal, char);
        return;
    }

    switch (to_action) {
        .CSI_DISPATCH => {
            switch (char) {
                'm' => handleSGR(terminal, state),

                'A' => { // Cursor Up
                    const n: usize = if (state.num_params > 0) @max(state.params[0], 1) else 1;
                    cursorUp(terminal, n);
                },
                'B' => { // Cursor Down
                    const n: usize = if (state.num_params > 0) @max(state.params[0], 1) else 1;
                    cursorDown(terminal, n);
                },
                'C' => { // Cursor Right
                    const n: usize = if (state.num_params > 0) @max(state.params[0], 1) else 1;
                    cursorRight(terminal, n);
                },
                'D' => { // Cursor Left
                    const n: usize = if (state.num_params > 0) @max(state.params[0], 1) else 1;
                    cursorLeft(terminal, n);
                },

                'H', 'f' => { // Cursor Position
                    const row = if (state.num_params > 0) state.params[0] else 1;
                    const col = if (state.num_params > 1) state.params[1] else 1;
                    setCursorPosition(terminal, row, col);
                },
                'J' => { // Erase in Display
                    const mode = if (state.num_params > 0) state.params[0] else 0;
                    terminal.grid.eraseDisplay(terminal.allocator, @enumFromInt(mode)) catch unreachable;
                },
                'K' => { // Erase in Line
                    const mode = if (state.num_params > 0) state.params[0] else 0;
                    terminal.grid.eraseLine(terminal.allocator, mode) catch unreachable;
                },
                'P' => { // DCH — Delete Character(s)
                    const n: usize = if (state.num_params > 0) @max(state.params[0], 1) else 1;
                    terminal.grid.deleteChars(terminal.allocator, n) catch unreachable;
                },
                'h' => {}, // Set Mode (ignore for now)
                'l' => {}, // Reset Mode (ignore for now)
                else => {},
            }
        },
        .ESC_DISPATCH => {
            if (state.num_intermediate_chars == 1 and state.intermediate_chars[0] == '(') {
                switch (char) {
                    '0' => terminal.emulator.charset = .dec_special_graphics,
                    'B' => terminal.emulator.charset = .ascii,
                    else => unreachable,
                }
            } else switch (char) {
                '=' => {}, // Application Keypad (ignore)
                '>' => {}, // Normal Keypad (ignore)
                else => {},
            }
        },
        .PRINT => printByte(terminal, char),
        .OSC_START => {
            terminal.emulator.ocs_buffer_len = 0;
        },
        .OSC_PUT => {
            std.debug.assert(terminal.emulator.ocs_buffer_len < terminal.emulator.ocs_buffer.len);

            terminal.emulator.ocs_buffer[terminal.emulator.ocs_buffer_len] = char;
            terminal.emulator.ocs_buffer_len += 1;
        },
        .OSC_END => {
            const payload = terminal.emulator.ocs_buffer[0..terminal.emulator.ocs_buffer_len];

            if (std.mem.startsWith(u8, payload, "9;4;")) {
                const args = payload[4..];

                var it = std.mem.splitScalar(u8, args, ';');

                const state_str = it.next() orelse return;
                const state_int = std.fmt.parseInt(u3, state_str, 10) catch return;

                const progress_str = it.next() orelse "0";
                const progress_int = std.fmt.parseInt(u32, progress_str, 10) catch return;

                terminal.emulator.progress_state = @enumFromInt(state_int);
                terminal.emulator.progress = @min(progress_int, 100);

                log.debug("progress: {} {}%", .{ terminal.emulator.progress_state, terminal.emulator.progress });

                return;
            }
        },
        .EXECUTE => {
            switch (char) {
                0x0A => {
                    terminal.grid.linefeed(terminal.allocator) catch unreachable;
                },
                0x0D => {
                    terminal.grid.carriageReturn();
                },
                0x08 => { // Backspace - move cursor left
                    backspace(terminal);
                },
                0x07 => {
                    if (terminal.emulator.bell_action_callback) |action|
                        action(terminal.emulator.bell_action_data);
                },
                0x50 => {
                    const count = if (state.num_params > 1) state.params[0] else 1;
                    terminal.grid.deleteChars(terminal.allocator, count) catch unreachable;
                },
                else => {},
            }
        },
        else => {},
    }

    log.debug("{0s} 0x{1x:02} {1c}", .{ @tagName(to_action), char });
}

fn handleSGR(term: *Terminal, state: *const vt.ParserData) void {
    // No params = reset
    if (state.num_params == 0) {
        term.emulator.current_style = term.emulator.default_style;
        return;
    }

    var i: usize = 0;

    const current_style = &term.emulator.current_style;

    while (i < state.num_params) : (i += 1) {
        const p = state.params[i];

        switch (p) {
            0 => current_style.* = term.emulator.default_style,

            1 => current_style.flags.bold = true,
            4 => current_style.flags.underline = true,
            5, 6 => current_style.flags.blink = true,
            7 => current_style.flags.inverse = true,
            9 => current_style.flags.strikethrough = true,

            22 => current_style.flags.bold = false,
            23 => current_style.flags.italic = false,
            24 => current_style.flags.underline = false,
            25 => current_style.flags.blink = false,
            27 => current_style.flags.inverse = false,
            29 => current_style.flags.strikethrough = false,

            30...37, 90...97 => {
                const is_bright = p >= 90;
                const base: u8 = if (is_bright) 90 else 30;
                const offset: u8 = if (is_bright) 8 else 0;
                const idx: u8 = @intCast((p - base) + offset);

                const color_index: color.ansi.ColorIndex = @enumFromInt(idx);
                const ansi_color = term.emulator.color_palette.get(color_index);
                current_style.fg_color = ansi_color;
            },
            40...47, 100...107 => {
                const is_bright = p >= 100;
                const base: u8 = if (is_bright) 100 else 40;
                const offset: u8 = if (is_bright) 8 else 0;
                const idx: u8 = @intCast((p - base) + offset);

                const color_index: color.ansi.ColorIndex = @enumFromInt(idx);
                const ansi_color = term.emulator.color_palette.get(color_index);
                current_style.bg_color = ansi_color;
            },

            38, 48 => {
                // 256-color: 38;5;N / 48;5;N
                if (i + 2 < state.num_params and
                    state.params[i + 1] == 5 and
                    state.params[i + 2] < 256)
                {
                    const color_index: color.ansi.ColorIndex = @enumFromInt(state.params[i + 2]);
                    const ansi_color = term.emulator.color_palette.get(color_index);

                    if (p == 38)
                        current_style.fg_color = ansi_color
                    else
                        current_style.bg_color = ansi_color;

                    i += 2;
                }
                // Truecolor: 38;2;R;G;B / 48;2;R;G;B
                else if (i + 4 < state.num_params and state.params[i + 1] == 2) {
                    const r = @as(u8, @intCast(state.params[i + 2]));
                    const g = @as(u8, @intCast(state.params[i + 3]));
                    const b = @as(u8, @intCast(state.params[i + 4]));
                    if (p == 38)
                        current_style.fg_color = .rgba(r, g, b, 255)
                    else
                        current_style.bg_color = .rgba(r, g, b, 255);
                    i += 4;
                }
            },

            39 => current_style.fg_color = term.emulator.default_style.fg_color,
            49 => current_style.bg_color = term.emulator.default_style.bg_color,

            else => {},
        }
    }

    log.debug("style update: {f}", .{term.emulator.current_style});
}

fn cursorUp(terminal: *Terminal, n: usize) void {
    terminal.grid.clearWrapPending();
    if (n > terminal.grid.cursor_y)
        terminal.grid.cursor_y = 0
    else
        terminal.grid.cursor_y -= n;
}

fn cursorDown(terminal: *Terminal, n: usize) void {
    terminal.grid.clearWrapPending();
    terminal.grid.cursor_y = @min(terminal.grid.cursor_y + n, terminal.grid.visable_rows -| 1);
}

fn cursorLeft(terminal: *Terminal, n: usize) void {
    terminal.grid.clearWrapPending();
    if (n > terminal.grid.cursor_x)
        terminal.grid.cursor_x = 0
    else
        terminal.grid.cursor_x -= n;
}

fn cursorRight(terminal: *Terminal, n: usize) void {
    terminal.grid.clearWrapPending();
    terminal.grid.cursor_x = @min(terminal.grid.cursor_x + n, terminal.grid.rows_width -| 1);
}

fn setCursorPosition(terminal: *Terminal, row: usize, col: usize) void {
    terminal.grid.clearWrapPending();
    terminal.grid.cursor_y = @min(row -| 1, terminal.grid.visable_rows -| 1);
    terminal.grid.cursor_x = @min(col -| 1, terminal.grid.rows_width -| 1);
}

/// Write one streamed byte. ASCII goes straight to the grid; the rest is
/// buffered until a full UTF-8 codepoint is available.
fn printByte(terminal: *Terminal, char: u8) void {
    if (char < 0x80) {
        flushUtf8(terminal);
        putCodepoint(terminal, translate(terminal.emulator.charset, char));
        return;
    }

    if (terminal.emulator.utf8_len == 0) {
        const expected = std.unicode.utf8ByteSequenceLength(char) catch 1;

        terminal.emulator.utf8_buf[0] = char;
        terminal.emulator.utf8_len = 1;

        if (terminal.emulator.utf8_len >= expected)
            flushUtf8(terminal);
    } else {
        const expected = std.unicode.utf8ByteSequenceLength(terminal.emulator.utf8_buf[0]) catch {
            putCodepoint(terminal, 0xFFFD); // stray continuation / invalid lead
            terminal.emulator.utf8_len = 0;
            return;
        };

        terminal.emulator.utf8_buf[terminal.emulator.utf8_len] = char;
        terminal.emulator.utf8_len += 1;

        if (terminal.emulator.utf8_len >= expected)
            flushUtf8(terminal);
    }
}

/// Decode the buffered bytes and emit one cell. A truncated sequence at the
/// end of the stream (or a control char interrupting it) becomes U+FFFD.
fn flushUtf8(terminal: *Terminal) void {
    if (terminal.emulator.utf8_len == 0) return;
    const expected = std.unicode.utf8ByteSequenceLength(terminal.emulator.utf8_buf[0]) catch 0;

    var codepoint: u21 = 0xFFFD;

    if (terminal.emulator.utf8_len == expected)
        codepoint = std.unicode.utf8Decode(terminal.emulator.utf8_buf[0..expected]) catch 0xFFFD;

    terminal.emulator.utf8_len = 0;
    putCodepoint(terminal, codepoint);
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
