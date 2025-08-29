const std = @import("std");

test "all" {
    std.testing.refAllDecls(@import("ChildProcess.zig"));
    std.testing.refAllDecls(@import("CircularBuffer.zig"));
    std.testing.refAllDecls(@import("DynamicLibrary.zig"));
    std.testing.refAllDecls(@import("input/Keyboard.zig"));
    std.testing.refAllDecls(@import("parser.zig"));
    std.testing.refAllDecls(@import("pty/root.zig"));
    std.testing.refAllDecls(@import("font/root.zig"));
}
