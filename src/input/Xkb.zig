const Xkb = @This();

pub const c = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    // @cInclude("xkbcommon/xkbcommon-x11.h");
});

ctx: *c.xkb_context,
keymap: *c.xkb_keymap,
state: *c.xkb_state,
// mods: ModIndcies,

const ModIndcies = struct {
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

    return .{
        .ctx = ctx,
        .keymap = keymap,
        .state = state,
    };
}
