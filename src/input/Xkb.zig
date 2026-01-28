const Xkb = @This();

const root = @import("root.zig");
const keyboard = root.keyboard;

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
};

pub fn init() !Xkb {
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
            .ctrl = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_CTRL)),
            .shift = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_SHIFT)),
            .alt = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_ALT)),
            .super = one << @intCast(c.xkb_keymap_mod_get_index(keymap, c.XKB_MOD_NAME_LOGO)),
        },
    };
}

pub fn deinit(self: *Xkb) void {
    c.xkb_state_unref(self.state);
    c.xkb_keymap_unref(self.keymap);
    c.xkb_context_unref(self.ctx);
}

pub fn getModifiers(self: *Xkb) keyboard.ModsState {
    const bitmask = c.xkb_state_serialize_mods(self.state, c.XKB_STATE_MODS_EFFECTIVE);

    const ctrl = (bitmask & self.mods.ctrl) != 0;
    const shift = (bitmask & self.mods.shift) != 0;
    const alt = (bitmask & self.mods.alt) != 0;
    const super = (bitmask & self.mods.super) != 0;

    const mods = keyboard.ModsState.init(.{
        .ctrl = ctrl,
        .shift = shift,
        .alt = alt,
        .super = super,
    });

    return mods;
}

pub fn handleEvent(self: *Xkb, event: root.keyboard.KeyEvent) void {
    self.updateKey(event.code, event.type == .press);
}

pub fn updateKey(self: *Xkb, keycode: u32, pressed: bool) void {
    const direction = if (pressed) c.XKB_KEY_DOWN else c.XKB_KEY_UP;
    _ = c.xkb_state_update_key(self.state, keycode, @intCast(direction));
}

pub fn keySym(self: *Xkb, keycode: u32) u32 {
    return c.xkb_state_key_get_one_sym(self.state, keycode);
}

pub fn keysymToUTF8(self: *Xkb, keysym: u32, buffer: []u8) usize {
    _ = self;
    const len = c.xkb_keysym_to_utf8(keysym, buffer.ptr, buffer.len);
    if (len < 0) return 0;
    return @intCast(len);
}

pub fn keysymToUTF32(self: *Xkb, keysym: u32) u32 {
    _ = self;
    return c.xkb_keysym_to_utf32(keysym);
}

pub fn updateKeyAndGetUTF8(self: *Xkb, keycode: u32, pressed: bool, buffer: []u8) usize {
    self.updateKey(keycode, pressed);
    if (!pressed) return 0;
    const keysym = self.keySym(keycode);
    return self.keysymToUTF8(keysym, buffer);
}

pub fn updateKeyAndGetUTF8Slice(self: *Xkb, keycode: u32, pressed: bool, buffer: []u8) []const u8 {
    const len = self.updateKeyAndGetUTF8(keycode, pressed, buffer);
    return buffer[0..len];
}

pub fn updateKeyAndGetUTF32(self: *Xkb, keycode: u32, pressed: bool) u32 {
    self.updateKey(keycode, pressed);
    if (!pressed) return 0;
    const keysym = self.keySym(keycode);
    return self.keysymToUTF32(keysym);
}

pub fn isPrintableKey(self: *Xkb, keycode: u32) bool {
    const sym = self.keySym(keycode);
    return sym >= 32 and sym <= 0x10FFFF;
}

pub fn setMods(self: *Xkb, mods: root.Modifiers) void {
    var mods_mask: u32 = 0;

    mods_mask |= if (mods.alt) self.mods.alt else 0;
    mods_mask |= if (mods.ctrl) self.mods.ctrl else 0;
    mods_mask |= if (mods.shift) self.mods.shift else 0;
    mods_mask |= if (mods.super) self.mods.super else 0;

    _ = c.xkb_state_update_mask(self.state, mods_mask, 0, 0, 0, 0, 0);
}
