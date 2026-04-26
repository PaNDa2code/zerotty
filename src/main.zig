const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const App = @import("App.zig");

pub fn main(init: std.process.Init) !void {
    var app = try App.init(init.gpa, init.io, init.environ_map);
    defer app.deinit();

    try app.run();
}

pub const panic = std.debug.FullPanic(panicHandle);

fn panicHandle(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.debug.defaultPanic(msg, first_trace_addr);
}

// export fn wWinMain(
//     hInstance: ?*anyopaque,
//     hPrevInstance: ?*anyopaque,
//     pCmdLine: *[*:0]const u16,
//     nCmdShow: i32,
// ) callconv(.winapi) i32 {
//     _ = hInstance;
//     _ = hPrevInstance;
//     _ = pCmdLine;
//     _ = nCmdShow;
//
//     const alloc = std.heap.c_allocator;
//     var threaded = std.Io.Threaded.init(alloc, .{});
//     defer threaded.deinit();
//
//     var app = App.init(alloc, threaded.io()) catch |err|
//         std.debug.panic("{}", .{err});
//     defer app.deinit();
//
//     app.run() catch |err|
//         std.debug.panic("{}", .{err});
//
//     return 0;
// }

pub const UNICODE = true;
