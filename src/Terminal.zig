const Terminal = @This();

pty: Pty,
shell: ChildProcess,
grid: Grid,
vtparser: vt.VTParser,

color_palette: color.ansi.Palette = .default,

current_style: struct {
    fg_color: color.RGBA = .white,
    bg_color: color.RGBA = .black,
    flags: color.ansi.Flags = .{},
} = .{},

pub const TerminalSettings = struct {
    shell_path: []const u8 = "",
    shell_args: []const []const u8 = &.{},
    rows: u32,
    cols: u32,
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
    });

    var shell = ChildProcess{
        .exe_path = settings.shell_path,
        .args = settings.shell_args,
    };
    try shell.start(io, environ_map, allocator, &pty);

    const grid = try Grid.init(allocator, .{
        .visable_columns = settings.cols,
        .visable_rows = settings.rows,
    });

    return .{
        .pty = pty,
        .shell = shell,
        .grid = grid,
        .vtparser = .init(vtparserCallback, null),
    };
}

pub fn deinit(self: *Terminal, _: std.mem.Allocator) void {
    self.pty.close();
    self.shell.terminate();
    self.grid.deinit();
}

fn vtparserCallback(state: *const vt.ParserData, to_action: vt.Action, char: u8, user_data: ?*anyopaque) void {
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));
    switch (to_action) {
        .CSI_DISPATCH => {
            if (char == 'm') {
                terminal.handleSGR(state);
            }
        },
        .PRINT => {
            terminal.grid.appendCell(.{
                .fg_color = terminal.current_style.fg_color,
                .bg_color = terminal.current_style.bg_color,
                .flags = terminal.current_style.flags,
                .unicode = @intCast(char),
            }) catch unreachable;
        },
        .EXECUTE => {
            switch (char) {
                0x0A => {
                    terminal.grid.appendRow() catch unreachable;
                },
                0x0D => {
                    // TODO: handle carriage return if needed
                    // Usually CR just moves cursor to column 0,
                    // but since appendCell/appendRow handles it implicitly for now,
                    // we might need more logic here later.
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
        term.current_style = .{};
        return;
    }

    var i: usize = 0;
    while (i < state.num_params) : (i += 1) {
        const p = state.params[i];

        switch (p) {
            0 => term.current_style = .{},

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

const std = @import("std");
const log = std.log.scoped(.vtparser);
const vt = @import("vtparse");
const color = @import("color");
const font = @import("font");
const Pty = @import("pty").Pty;
const ChildProcess = @import("ChildProcess");
const Scrollback = @import("Scrollback.zig");
const Grid = @import("grid/root.zig").Grid;
