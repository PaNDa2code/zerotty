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

pub const ModsState = std.enums.EnumSet(Mod);

pub const KeyEventType = enum {
    press,
    release,
    repeat,
};

pub const KeyEvent = struct {
    type: KeyEventType,
    state: KeyboardState,
    code: u32,
};
