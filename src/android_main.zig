const std = @import("std");
const native = @import("android_native_glue");

const App = @import("App.zig");

pub const std_options = std.Options{
    .logFn = androidLogFn,
};

extern fn __android_log_write(prio: AndroidLogPriority, tag: [*:0]const u8, text: [*:0]const u8) void;

const AndroidLogPriority = enum(c_int) {
    unknown = 0,
    default,
    verbose,
    debug,
    info,
    warn,
    @"error",
    fatal,
    silent,
};

const max_logging_bytes = 2048;

fn androidLogFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const prio: AndroidLogPriority = switch (message_level) {
        .debug => .debug,
        .err => .@"error",
        .info => .info,
        .warn => .warn,
    };
    const tag = @tagName(scope);

    var buffer: [max_logging_bytes]u8 = undefined;

    const text = std.fmt.bufPrintSentinel(&buffer, format, args, 0) catch
        std.debug.panic("max logging bytes is {}", .{max_logging_bytes});

    __android_log_write(prio, tag.ptr, text.ptr);
}

pub const panic = std.debug.FullPanic(panicHandle);

fn panicHandle(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.debug.defaultPanic(msg, first_trace_addr);
}

export fn android_main(state: *native.android_app) callconv(.c) void {
    native.app_dummy();

    std.log.debug("running android_main", .{});

    const allocator = std.heap.c_allocator;

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
    state.onInputEvent = onInputEvent;

    var app = App.init(init.gpa, init.io, init.environ_map) catch @panic("App creation failed");
    defer app.deinit();

    var events: c_int = undefined;
    var source: [*c]native.android_poll_source = null;

    while (true) {
        const ident = native.ALooper_pollAll(-1, null, &events, @ptrCast(&source));

        if (ident >= 0) {
            if (source != null) {
                if (source.*.process) |process_fn| {
                    process_fn(state, source);
                }
            }
        }

        if (state.destroyRequested != 0) {
            std.log.debug("App destruction requested. Exiting loop.", .{});
            break;
        }
    }
}

fn testAysnc() void {
    std.log.debug("Hello from testAysnc", .{});
}

fn onAppCmd(_app: [*c]native.android_app, _cmd: i32) callconv(.c) void {
    const app: *native.android_app = @ptrCast(_app);
    _ = app;

    const cmd = @as(AppCmd, @enumFromInt(_cmd));

    switch (cmd) {
        .init_window => {},
        .term_window => {},
        else => {},
    }

    std.log.debug("onAppCmd(app, {})", .{cmd});
}

fn onInputEvent(
    _app: [*c]native.android_app,
    _event: ?*native.AInputEvent,
) callconv(.c) i32 {
    const app: *native.android_app = @ptrCast(_app);
    _ = app;

    std.log.debug("onInputEvent(app, {any})", .{_event});

    return 0;
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
