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

pub const UNICODE = true;

test {
    // std.testing.refAllDecls(@import("ChildProcess.zig"));
    // std.testing.refAllDecls(@import("CircularBuffer.zig"));
    // std.testing.refAllDecls(@import("DynamicLibrary.zig"));
    // std.testing.refAllDecls(@import("Keyboard.zig"));
    // std.testing.refAllDecls(@import("parser.zig"));
    // std.testing.refAllDecls(@import("pty/root.zig"));
    std.testing.refAllDecls(@import("font/root.zig"));
}
