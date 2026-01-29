const std = @import("std");

pub const keyboard_key_count = 256;
// Can be stored in AVX register (YMMx)
pub const KeyboardState = std.bit_set.IntegerBitSet(keyboard_key_count);

pub const Mod = enum {
    shift,
    ctrl,
    alt,
    super,
    caps,
    num,
};


pub const ModState = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    caps: bool = false,
    num: bool = false,
};

pub const KeyEventType = enum {
    press,
    release,
    repeat,
};

pub const KeyEvent = struct {
    type: KeyEventType,
    mods: ModState,
    code: u32,
};

pub const Xkb = @import("Xkb.zig");
