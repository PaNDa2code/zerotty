const Terminal = @This();

pty: Pty,
shell: ChildProcess,
grid: Grid,
vtparser: vt.VTParser,

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

pub fn init(allocator: std.mem.Allocator, settings: TerminalSettings) !Terminal {
    var pty: Pty = undefined;
    try pty.open(.{
        .shell = .bash,
        .async_io = true,
    });

    var shell = ChildProcess{
        .exe_path = settings.shell_path,
        .args = settings.shell_args,
    };
    try shell.start(allocator, &pty);

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
                .code = @intCast(char),
            }) catch unreachable;
        },
        else => {},
    }

    std.log.debug("{} {}", .{ to_action, char });
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

            // 30...37 => term.current_style.fg_color = ansiFg(p),
            // 40...47 => term.current_style.bg_color = ansiBg(p),
            //
            // 90...97 => term.current_style.fg_color = ansiBrightFg(p),
            // 100...107 => term.current_style.bg_color = ansiBrightBg(p),

            // 256-color: 38;5;N / 48;5;N
            // 38, 48 => {
            //     if (i + 2 < state.num_params and state.params[i + 1] == 5) {
            //         const color_index = state.params[i + 2];
            //         if (p == 38)
            //             term.current_style.fg_color = Color.ansi256(color_index)
            //         else
            //             term.current_style.bg_color = Color.ansi256(color_index);
            //         i += 2;
            //     }
            // },

            // Truecolor: 38;2;R;G;B / 48;2;R;G;B
            38, 48 => {
                if (i + 4 < state.num_params and state.params[i + 1] == 2) {
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
}

const std = @import("std");
const vt = @import("vtparse");
const color = @import("color");
const Pty = @import("pty").Pty;
const ChildProcess = @import("ChildProcess");
const Scrollback = @import("Scrollback.zig");
const Grid = @import("grid/root.zig").Grid;
