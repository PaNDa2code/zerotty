const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const App = @import("App.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();

    const allocator =
        if (builtin.mode == .Debug)
            debug_allocator.allocator()
        else
            std.heap.c_allocator;

    var app = try App.init(allocator);
    defer app.deinit();

    try app.run();
}

pub const panic = std.debug.FullPanic(panicHandle);

fn panicHandle(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.debug.defaultPanic(msg, first_trace_addr);
}

export fn wWinMain() callconv(.winapi) i32 {
    main() catch |e| {
        std.debug.panic("{}", .{e});
    };
    return 0;
}

pub const UNICODE = true;

test {
    std.testing.refAllDecls(@import("test.zig"));
}
