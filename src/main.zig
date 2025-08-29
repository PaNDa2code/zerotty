const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const App = @import("App.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.new(allocator);
    try app.start();
    defer app.exit();

    app.loop();
}

pub const panic = std.debug.FullPanic(panic_handler);

fn panic_handler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.debug.defaultPanic(msg, first_trace_addr);
}

export fn wWinMain() callconv(std.os.windows.WINAPI) i32 {
    main() catch |e| {
        std.debug.panic("{}", .{e});
    };
    return 0;
}

pub const UNICODE = true;

test {
    std.testing.refAllDecls(@import("test.zig"));
}
