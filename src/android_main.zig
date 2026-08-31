const std = @import("std");
const native = @import("android_native_glue");

export fn android_main(state: *native.android_app) callconv(.c) void {
    native.app_dummy();

    const allocator = std.heap.smp_allocator;

    var init = allocator.create(std.process.Init) catch @panic("OOM");

    init.gpa = allocator;

    init.arena = init.gpa.create(std.heap.ArenaAllocator) catch @panic("OOM");
    init.arena.* = .init(init.gpa);

    var threaded_io = init.gpa.create(std.Io.Threaded) catch @panic("OOM");

    threaded_io.* = .init(init.gpa, .{});
    init.io = threaded_io.io();

    init.preopens = .empty;

    init.environ_map = init.gpa.create(std.process.Environ.Map) catch @panic("OOM");
    init.environ_map.* = .init(init.gpa);

    init.minimal.args.vector = &.{};
    init.minimal.environ = .empty;

    state.userData = init;
    state.onAppCmd = onAppCmd;
}

fn onAppCmd(app_: [*c]native.android_app, cmd: i32) callconv(.c) void {
    const app: *native.android_app = @ptrCast(app_);
    _ = app;

    switch (@as(AppCmd, @enumFromInt(cmd))) {
        .init_window => {},
        .term_window => {},
        else => {},
    }
}

const AppCmd = enum(i32) {
    input_changed = native.APP_CMD_INPUT_CHANGED,

    init_window = native.APP_CMD_INIT_WINDOW,

    term_window = native.APP_CMD_TERM_WINDOW,

    window_resized = native.APP_CMD_WINDOW_RESIZED,

    window_redraw_needed = native.APP_CMD_WINDOW_REDRAW_NEEDED,

    content_rect_changed = native.APP_CMD_CONTENT_RECT_CHANGED,

    gained_focus = native.APP_CMD_GAINED_FOCUS,

    lost_focus = native.APP_CMD_LOST_FOCUS,

    config_changed = native.APP_CMD_CONFIG_CHANGED,

    low_memory = native.APP_CMD_LOW_MEMORY,

    start = native.APP_CMD_START,

    @"resume" = native.APP_CMD_RESUME,

    save_state = native.APP_CMD_SAVE_STATE,

    pause = native.APP_CMD_PAUSE,

    stop = native.APP_CMD_STOP,

    destroy = native.APP_CMD_DESTROY,

    _,
};
