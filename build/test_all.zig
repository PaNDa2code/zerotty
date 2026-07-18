const std = @import("std");
const builtin = @import("builtin");

test {
    std.testing.refAllDecls(@import("window"));
}
