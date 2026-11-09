const Terminal = @This();

const std = @import("std");
const vt = @import("vt.zig");
const zerotty = @import("zerotty");
const color = zerotty.terminal.color;
const Grid = zerotty.terminal.grid.Grid;

const Emulator = @import("Emulator.zig");
const Session = @import("Session.zig");

allocator: std.mem.Allocator,

grid: Grid,
session: Session,
vtparser: vt.Parser,
decoder: vt.Decoder,
emulator: Emulator,

/// Grid saved while the alternate screen is active. `null` means the main
/// screen is active.
saved_grid: ?Grid = null,

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
) !*Terminal {
    const terminal = try allocator.create(Terminal);
    errdefer allocator.destroy(terminal);

    const session = try Session.init(
        io,
        environ_map,
        allocator,
        settings.shell_path,
        settings.shell_args,
        @intCast(settings.rows),
        @intCast(settings.cols),
    );
    errdefer terminal.session.deinit();

    const style = Emulator.Style{
        .fg_color = settings.fg_color,
        .bg_color = settings.bg_color,
    };

    terminal.* = .{
        .session = session,
        .allocator = allocator,
        .grid = .{
            .visable_rows = settings.rows,
            .rows_width = settings.cols,
            .bg_color = settings.bg_color,
        },
        .vtparser = .init(vt.vtparserEntry, terminal),
        .decoder = .{},
        .emulator = .{
            .default_style = style,
            .current_style = style,
        },
    };

    return terminal;
}

/// Switch between the main and alternate screens. Entering the alternate screen
/// saves the current grid and starts with a blank one; leaving it restores the
/// saved grid (including its cursor and scroll region).
pub fn setAltScreen(self: *Terminal, on: bool) !void {
    if (on) {
        if (self.saved_grid != null) return;

        self.saved_grid = self.grid;
        self.grid = .{
            .visable_rows = self.saved_grid.?.visable_rows,
            .rows_width = self.saved_grid.?.rows_width,
            .max_scrollback = 0,
            .bg_color = self.saved_grid.?.bg_color,
        };
        return;
    }

    if (self.saved_grid) |saved| {
        const rows = self.grid.visable_rows;
        const cols = self.grid.rows_width;

        self.grid.deinit(self.allocator);
        self.grid = saved;
        self.saved_grid = null;

        // The window may have been resized while the alternate screen was
        // active. Bring the restored main screen up to date.
        self.grid.resizeVisable(self.allocator, rows, cols) catch {};
    }
}

pub fn deinit(self: *Terminal) void {
    self.session.deinit();
    self.grid.deinit(self.allocator);
    if (self.saved_grid) |*saved| saved.deinit(self.allocator);
    self.allocator.destroy(self);
}
