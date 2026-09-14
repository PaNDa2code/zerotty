//! InputHandler centralises all terminal input encoding.
const InputHandler = @This();

const std = @import("std");
const zerotty = @import("zerotty");
const input = zerotty.system.input;
const keyboard = input.keyboard;
const Key = keyboard.Key;
const KeyEvent = keyboard.KeyEvent;
const InputEvent = input.InputEvent;
const Grid = zerotty.terminal.Grid;

/// Anything the handler needs to forward output to.
pub const Sink = struct {
    /// Write bytes into the PTY.
    writeFn: *const fn (sink: *Sink, io: std.Io, data: []const u8) anyerror!void,
    /// Scroll the viewport up by N lines (does NOT write to PTY).
    scrollUpFn: *const fn (sink: *Sink, lines: u32) void,
    /// Scroll the viewport down by N lines.
    scrollDownFn: *const fn (sink: *Sink, lines: u32) void,
    /// Snap the viewport back to the bottom.
    scrollToBottomFn: *const fn (sink: *Sink) void,
    /// Paste text from the clipboard.
    pasteFn: *const fn (sink: *Sink, io: std.Io) anyerror!void,
    /// Change the terminal font size: delta > 0 zooms in, delta < 0 zooms out.
    fontSizeFn: *const fn (sink: *Sink, delta: i32) void,

    pub fn write(self: *Sink, io: std.Io, data: []const u8) anyerror!void {
        return self.writeFn(self, io, data);
    }
    pub fn scrollUp(self: *Sink, lines: u32) void {
        self.scrollUpFn(self, lines);
    }
    pub fn scrollDown(self: *Sink, lines: u32) void {
        self.scrollDownFn(self, lines);
    }
    pub fn scrollToBottom(self: *Sink) void {
        self.scrollToBottomFn(self);
    }
    pub fn paste(self: *Sink, io: std.Io) anyerror!void {
        return self.pasteFn(self, io);
    }
    pub fn changeFontSize(self: *Sink, delta: i32) void {
        self.fontSizeFn(self, delta);
    }
};

/// Process a single `InputEvent`. Call this from `App.zig`'s event loop.
pub fn handle(sink: *Sink, io: std.Io, event: InputEvent) !void {
    switch (event) {
        // ── Printable characters ──────────────────────────────────────────
        // utf8_codepoint is emitted by platforms for every printable keypress.
        // We encode it to UTF-8 and write it to the PTY.
        // Keyboard events for printable keys are intentionally ignored here
        // to avoid double-input on platforms (e.g. Linux) that emit both.
        .utf8_codepoint =>
        // |cp|
        {
            // var buf: [4]u8 = undefined;
            // const len = try std.unicode.utf8Encode(cp, &buf);
            // try sink.write(io, buf[0..len]);
        },

        // ── Keyboard events ───────────────────────────────────────────────
        .keyboard => |kev| {
            // Only act on press and repeat; ignore release.
            if (kev.type == .release) return;
            try handleKey(sink, io, kev);
        },

        // ── Mouse events ──────────────────────────────────────────────────
        .mouse => |mev| {
            switch (mev) {
                .scroll => |s| {
                    const lines: i32 = @intFromFloat(s.y_offset * 3.0);
                    if (lines > 0)
                        sink.scrollUp(@intCast(lines))
                    else if (lines < 0)
                        sink.scrollDown(@intCast(-lines));
                },
                // Button / move events could drive mouse reporting here later.
                else => {},
            }
        },
    }
}

fn handleKey(sink: *Sink, io: std.Io, kev: KeyEvent) !void {
    const ctrl = kev.mods.ctrl;
    const shift = kev.mods.shift;
    const alt = kev.mods.alt;

    if (ctrl and shift) {
        switch (kev.key) {
            .v => {
                try sink.paste(io);
                return;
            },
            .c => return,
            else => {},
        }
    }

    if (alt and !ctrl) {
        if (altSequence(kev.key)) |seq| {
            try sink.write(io, seq);
            return;
        }
    }

    if (ctrl and !shift) {
        switch (kev.key) {
            .equal, .kp_add => {
                sink.changeFontSize(1);
                return;
            },
            .minus, .kp_subtract => {
                sink.changeFontSize(-1);
                return;
            },
            else => {},
        }

        if (ctrlSequence(kev.key)) |seq| {
            try sink.write(io, seq);
            return;
        }
        const ki = @intFromEnum(kev.key);
        if (ki >= 'a' and ki <= 'z') {
            const byte: u8 = @intCast(ki & 0x1F);
            try sink.write(io, &.{byte});
            return;
        }
    }

    if (specialSequence(kev.key, kev.mods)) |seq| {
        switch (kev.key) {
            .page_up => {
                sink.scrollUp(10);
                return;
            },
            .page_down => {
                sink.scrollDown(10);
                return;
            },
            else => {},
        }
        try sink.write(io, seq);
        return;
    }

    if (!ctrl and !alt) {
        const ki = @intFromEnum(kev.key);
        if (ki >= ' ' and ki <= '~') {
            const ch: u8 = if (shift) shiftChar(@intCast(ki)) else @intCast(ki);
            try sink.write(io, &.{ch});
        }
    }
}

fn specialSequence(key: Key, mods: keyboard.ModState) ?[]const u8 {
    return switch (key) {
        .arrow_up => if (mods.shift) "\x1b[1;2A" else "\x1b[A",
        .arrow_down => if (mods.shift) "\x1b[1;2B" else "\x1b[B",
        .arrow_right => if (mods.shift) "\x1b[1;2C" else "\x1b[C",
        .arrow_left => if (mods.shift) "\x1b[1;2D" else "\x1b[D",

        // Editing keys
        .home => "\x1b[H",
        .end => "\x1b[F",
        .insert => "\x1b[2~",
        .delete => "\x1b[3~",
        .page_up => "\x1b[5~",
        .page_down => "\x1b[6~",

        // Control keys
        .enter => "\r",
        .backspace => "\x7f",
        .tab => if (mods.shift) "\x1b[Z" else "\t", // Shift+Tab = reverse tab
        .escape => "\x1b",

        // Function keys (standard xterm encoding)
        .f1 => "\x1bOP",
        .f2 => "\x1bOQ",
        .f3 => "\x1bOR",
        .f4 => "\x1bOS",
        .f5 => "\x1b[15~",
        .f6 => "\x1b[17~",
        .f7 => "\x1b[18~",
        .f8 => "\x1b[19~",
        .f9 => "\x1b[20~",
        .f10 => "\x1b[21~",
        .f11 => "\x1b[23~",
        .f12 => "\x1b[24~",

        // Numpad (numeric mode — application mode can be added later)
        .kp_enter => "\r",
        .kp_0 => "0",
        .kp_1 => "1",
        .kp_2 => "2",
        .kp_3 => "3",
        .kp_4 => "4",
        .kp_5 => "5",
        .kp_6 => "6",
        .kp_7 => "7",
        .kp_8 => "8",
        .kp_9 => "9",
        .kp_decimal => ".",
        .kp_divide => "/",
        .kp_multiply => "*",
        .kp_subtract => "-",
        .kp_add => "+",
        .kp_equal => "=",

        else => null,
    };
}

/// Well-known Ctrl+key sequences that don't follow the generic Ctrl+letter rule.
fn ctrlSequence(key: Key) ?[]const u8 {
    return switch (key) {
        .enter => "\r",
        .backspace => "\x08", // Ctrl+Backspace → BS
        .tab => "\x00", // Ctrl+Tab → NUL (some terminals)
        .escape => "\x1b",
        .space => "\x00", // Ctrl+Space → NUL
        .left_bracket => "\x1b", // Ctrl+[ → ESC
        .backslash => "\x1c", // Ctrl+\ → FS
        .right_bracket => "\x1d", // Ctrl+] → GS
        .grave => "\x1e", // Ctrl+^ → RS (some layouts)
        .slash => "\x1f", // Ctrl+/ → US
        else => null,
    };
}

/// Alt+key sequences: ESC followed by the normal key encoding.
fn altSequence(key: Key) ?[]const u8 {
    return switch (key) {
        .arrow_up => "\x1b[1;3A",
        .arrow_down => "\x1b[1;3B",
        .arrow_right => "\x1b[1;3C",
        .arrow_left => "\x1b[1;3D",
        else => null,
    };
}

/// xterm modifier parameter: 1-based bitmask of Shift(1)/Alt(2)/Ctrl(4).
fn modParam(mods: keyboard.ModState) u8 {
    var m: u8 = 1;
    if (mods.shift) m += 1;
    if (mods.alt) m += 2;
    if (mods.ctrl) m += 4;
    return m;
}

/// Apply keyboard shift to an ASCII character.
fn shiftChar(ch: u8) u8 {
    return switch (ch) {
        'a'...'z' => ch - 32,
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '0' => ')',
        '-' => '_',
        '=' => '+',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        ';' => ':',
        '\'' => '"',
        ',' => '<',
        '.' => '>',
        '/' => '?',
        '`' => '~',
        else => ch,
    };
}
