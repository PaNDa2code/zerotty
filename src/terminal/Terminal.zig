const Terminal = @This();

allocator: std.mem.Allocator,

pty: Pty,
shell: ChildProcess,
grid: Grid,
vtparser: vt.VTParser,

/// progress bar value from 0-100
progress: u32 = 0,
/// progress bar state
progress_state: ProgressBarState = .remove,

bell_action_callback: ?*const fn (?*anyopaque) void = null,
bell_action_data: ?*anyopaque = null,

ocs_buffer: [128]u8 = [1]u8{0} ** 128,
ocs_buffer_len: usize = 0,

color_palette: color.ansi.Palette = .default,

default_style: Style,
current_style: Style,

const Style = struct {
    fg_color: color.RGBA,
    bg_color: color.RGBA,
    flags: color.ansi.Flags = .{},
};

pub const TerminalSettings = struct {
    shell_path: []const u8 = "",
    shell_args: []const []const u8 = &.{},
    rows: u32,
    cols: u32,
    fg_color: color.RGBA,
    bg_color: color.RGBA,
};

pub const ProgressBarState = enum(u3) {
    remove = 0,
    set = 1,
    @"error" = 2,
    indeterminate = 3,
    pause = 4,
};

pub fn init(
    io: std.Io,
    environ_map: *std.process.Environ.Map,
    allocator: std.mem.Allocator,
    settings: TerminalSettings,
) !Terminal {
    var pty: Pty = undefined;
    try pty.open(.{
        .shell = .bash,
        .async_io = true,
        .size = .{
            .height = @intCast(settings.rows),
            .width = @intCast(settings.cols),
        },
    });

    var shell = ChildProcess{
        .exe_path = settings.shell_path,
        .args = settings.shell_args,
    };
    try shell.start(io, environ_map, allocator, &pty);

    const style = Style{
        .fg_color = settings.fg_color,
        .bg_color = settings.bg_color,
    };

    return .{
        .pty = pty,
        .shell = shell,
        .allocator = allocator,
        .grid = .{
            .visable_rows = settings.rows,
            .rows_width = settings.cols,
            .bg_color = settings.bg_color,
        },
        .vtparser = .init(vtparserCallback, null),
        .default_style = style,
        .current_style = style,
    };
}

pub fn deinit(self: *Terminal, _: std.mem.Allocator) void {
    self.pty.close();
    self.shell.terminate();
    self.grid.deinit(self.allocator);
}

fn vtparserCallback(state: *const vt.ParserData, to_action: vt.Action, char: u8, user_data: ?*anyopaque) void {
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));
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
        .ESC_DISPATCH => switch (char) {
            '=' => {}, // Application Keypad (ignore)
            '>' => {}, // Normal Keypad (ignore)
            else => {},
        },
        .PRINT => {
            terminal.grid.putChar(terminal.allocator, .{
                .fg_color = terminal.current_style.fg_color,
                .bg_color = terminal.current_style.bg_color,
                .flags = terminal.current_style.flags,
                .unicode = @intCast(char),
            }) catch unreachable;
        },
        .OSC_START => {
            terminal.ocs_buffer_len = 0;
        },
        .OSC_PUT => {
            std.debug.assert(terminal.ocs_buffer_len < terminal.ocs_buffer.len);

            terminal.ocs_buffer[terminal.ocs_buffer_len] = char;
            terminal.ocs_buffer_len += 1;
        },
        .OSC_END => {
            const payload = terminal.ocs_buffer[0..terminal.ocs_buffer_len];

            if (std.mem.startsWith(u8, payload, "9;4;")) {
                const args = payload[4..];

                var it = std.mem.splitScalar(u8, args, ';');

                const state_str = it.next() orelse return;
                const state_int = std.fmt.parseInt(u3, state_str, 10) catch return;

                const progress_str = it.next() orelse "0";
                const progress_int = std.fmt.parseInt(u32, progress_str, 10) catch return;

                terminal.progress_state = @enumFromInt(state_int);
                terminal.progress = @min(progress_int, 100);

                log.debug("progress: {} {}%", .{ terminal.progress_state, terminal.progress });

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
                    if (terminal.bell_action_callback) |action|
                        action(terminal.bell_action_data);
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
        term.current_style = term.default_style;
        return;
    }

    var i: usize = 0;
    while (i < state.num_params) : (i += 1) {
        const p = state.params[i];

        switch (p) {
            0 => term.current_style = term.default_style,

            1 => term.current_style.flags.bold = true,
            4 => term.current_style.flags.underline = true,
            // 7 => term.current_style.flags.inverse = true,

            30...37, 90...97 => {
                const is_bright = p >= 90;
                const base: u8 = if (is_bright) 90 else 30;
                const offset: u8 = if (is_bright) 8 else 0;
                const idx: u8 = @intCast((p - base) + offset);

                const color_index: color.ansi.ColorIndex = @enumFromInt(idx);
                const ansi_color = term.color_palette.get(color_index);
                term.current_style.fg_color = ansi_color;
            },
            40...47, 100...107 => {
                const is_bright = p >= 100;
                const base: u8 = if (is_bright) 100 else 40;
                const offset: u8 = if (is_bright) 8 else 0;
                const idx: u8 = @intCast((p - base) + offset);

                const color_index: color.ansi.ColorIndex = @enumFromInt(idx);
                const ansi_color = term.color_palette.get(color_index);
                term.current_style.bg_color = ansi_color;
            },

            38, 48 => {
                // 256-color: 38;5;N / 48;5;N
                if (i + 2 < state.num_params and state.params[i + 1] == 5) {
                    std.debug.assert(state.params[i + 2] > 256 and state.params[i + 2] < 256);
                    const color_index: color.ansi.ColorIndex = @enumFromInt(state.params[i + 2]);
                    const ansi_color = term.color_palette.get(color_index);

                    if (p == 38)
                        term.current_style.fg_color = ansi_color
                    else
                        term.current_style.bg_color = ansi_color;

                    i += 2;
                }
                // Truecolor: 38;2;R;G;B / 48;2;R;G;B
                else if (i + 4 < state.num_params and state.params[i + 1] == 2) {
                    const r = @as(u8, @intCast(state.params[i + 2]));
                    const g = @as(u8, @intCast(state.params[i + 3]));
                    const b = @as(u8, @intCast(state.params[i + 4]));
                    if (p == 38)
                        term.current_style.fg_color = .rgba(r, g, b, 255)
                    else
                        term.current_style.bg_color = .rgba(r, g, b, 255);
                    i += 4;
                }
            },

            else => {},
        }
    }

    log.debug("{any}", .{term.current_style});
}

fn cursorUp(terminal: *Terminal, n: usize) void {
    if (n > terminal.grid.cursor_y)
        terminal.grid.cursor_y = 0
    else
        terminal.grid.cursor_y -= n;
}

fn cursorDown(terminal: *Terminal, n: usize) void {
    terminal.grid.cursor_y = @min(terminal.grid.cursor_y + n, terminal.grid.visable_rows -| 1);
}

fn cursorLeft(terminal: *Terminal, n: usize) void {
    if (n > terminal.grid.cursor_x)
        terminal.grid.cursor_x = 0
    else
        terminal.grid.cursor_x -= n;
}

fn cursorRight(terminal: *Terminal, n: usize) void {
    terminal.grid.cursor_x = @min(terminal.grid.cursor_x + n, terminal.grid.rows_width -| 1);
}

fn setCursorPosition(terminal: *Terminal, row: usize, col: usize) void {
    terminal.grid.cursor_y = @min(row -| 1, terminal.grid.visable_rows -| 1);
    terminal.grid.cursor_x = @min(col -| 1, terminal.grid.rows_width -| 1);
}

fn backspace(terminal: *Terminal) void {
    if (terminal.grid.cursor_x > 0)
        terminal.grid.cursor_x -= 1;
}

const std = @import("std");
const log = std.log.scoped(.vtparser);
const vt = @import("vtparse");
const zerotty = @import("zerotty");
const color = zerotty.terminal.color;
const font = zerotty.font;
const Pty = zerotty.system.pty.Pty;
const ChildProcess = zerotty.system.ChildProcess;
const Scrollback = @import("Scrollback.zig");
const Grid = @import("grid/root.zig").Grid;
