const std = @import("std");
const builtin = @import("builtin");

pub extern "log" fn __android_log_write(prio: c_int, tag: [*c]const u8, text: [*c]const u8) c_int;
pub extern "log" fn __android_log_print(prio: c_int, tag: [*c]const u8, text: [*c]const u8, ...) c_int;


pub const main = @import("main.zig").main;

const c = @cImport({
    @cInclude("android_native_app_glue.h");
});

export fn android_main(app_state: *c.android_app) callconv(.c) c_int {
    _ = app_state;
    return 0;
}

pub const panic = std.debug.no_panic;
