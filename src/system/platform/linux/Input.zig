const Input = @This();

const root = @import("../../input/root.zig");
const keyboard = root.keyboard;
const mouse = root.mouse;

pub const c = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    // @cInclude("xkbcommon/xkbcommon-x11.h");
});

ctx: *c.xkb_context,
keymap: *c.xkb_keymap,
state: *c.xkb_state,
mods: ModifiersMask,

const ModifiersMask = struct {
    ctrl: u32,
    shift: u32,
    alt: u32,
    super: u32,
    caps: u32,
    num: u32,
};

pub fn init() !Input {
    const ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse return error.NoMemory;

    var names: c.struct_xkb_rule_names = .{
        .rules = "evdev",
        .model = "pc105",
        .layout = "us",
        .variant = null,
        .options = null,
    };

    const keymap = c.xkb_keymap_new_from_names(
        ctx,
        &names,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse return error.KeymapInitFailed;

    const state = c.xkb_state_new(keymap) orelse return error.StateInitFailed;

    const one: u32 = 1;

    return .{
        .ctx = ctx,
        .keymap = keymap,
        .state = state,
        .mods = .{
            .ctrl  = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_CTRL)),
            .shift = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_SHIFT)),
            .alt   = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_ALT)),
            .super = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_LOGO)),
            .caps  = one << @intCast(c.xkb_keymap_mod_get_index(keymap, "Lock")),
            .num   = one << @intCast(c.xkb_keymap_mod_get_index(keymap, "Mod2")),
        },
    };
}

pub fn deinit(self: *Input) void {
    c.xkb_state_unref(self.state);
    c.xkb_keymap_unref(self.keymap);
    c.xkb_context_unref(self.ctx);
}

/// Return the current modifier state as a `ModState`.
pub fn getModState(self: *const Input) keyboard.ModState {
    const bitmask = c.xkb_state_serialize_mods(self.state, c.XKB_STATE_MODS_EFFECTIVE);
    return .{
        .ctrl  = (bitmask & self.mods.ctrl)  != 0,
        .shift = (bitmask & self.mods.shift) != 0,
        .alt   = (bitmask & self.mods.alt)   != 0,
        .super = (bitmask & self.mods.super) != 0,
        .caps  = (bitmask & self.mods.caps)  != 0,
        .num   = (bitmask & self.mods.num)   != 0,
    };
}

/// Update xkb state for a keycode transition and return a fully-populated
/// `KeyEvent` with `key` resolved to the platform-neutral `Key` enum.
pub fn processKey(self: *Input, keycode: u32, event_type: keyboard.KeyEventType) keyboard.KeyEvent {
    const direction: c_int = if (event_type == .press or event_type == .repeat)
        c.XKB_KEY_DOWN
    else
        c.XKB_KEY_UP;

    _ = c.xkb_state_update_key(self.state, keycode, @intCast(direction));

    const sym = c.xkb_state_key_get_one_sym(self.state, keycode);

    return .{
        .type  = event_type,
        .mods  = self.getModState(),
        .code  = keycode,
        .key   = keyboard.keyFromXkbKeysym(sym),
    };
}

/// Return the UTF-32 codepoint for the current key + state, or 0 if not printable.
/// Only meaningful on `.press` events.
pub fn keyToUTF32(self: *const Input, keycode: u32) u32 {
    const sym = c.xkb_state_key_get_one_sym(self.state, keycode);
    return c.xkb_keysym_to_utf32(sym);
}

/// Return the UTF-8 string for the current key + state (may be multi-byte).
/// `buffer` must be at least 5 bytes. Returns the number of bytes written.
pub fn keyToUTF8(self: *const Input, keycode: u32, buffer: []u8) usize {
    const sym = c.xkb_state_key_get_one_sym(self.state, keycode);
    const len = c.xkb_keysym_to_utf8(sym, buffer.ptr, buffer.len);
    if (len <= 0) return 0;
    return @intCast(len);
}

/// Convert an XCB button number to a `MouseButton`.
pub fn xcbButtonToMouse(detail: u8) ?mouse.MouseButton {
    return switch (detail) {
        1 => .left,
        2 => .middle,
        3 => .right,
        4, 5 => null, // scroll — handled separately as scroll event
        else => null,
    };
}

/// Convert an XCB scroll button detail (4 = up, 5 = down) to a `MouseScrollEvent`.
pub fn xcbScrollEvent(detail: u8) ?mouse.MouseScrollEvent {
    return switch (detail) {
        4 => .{ .x_offset = 0.0, .y_offset =  1.0 },
        5 => .{ .x_offset = 0.0, .y_offset = -1.0 },
        6 => .{ .x_offset = -1.0, .y_offset = 0.0 },
        7 => .{ .x_offset =  1.0, .y_offset = 0.0 },
        else => null,
    };
}
