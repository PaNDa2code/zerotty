const c = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-x11.h");
});

pub const Context = struct {
    ctx: *c.xkb_context,

    pub fn new() !Context {
        return .{
            .ctx = c.xkb_context_new(0) orelse
                return error.ContextCreationFailed,
        };
    }
};
