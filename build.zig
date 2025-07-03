const std = @import("std");
const Build = std.Build;

const exe_build = @import("build/exe_build.zig");
const wasm_build = @import("build/wasm_build.zig");

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.cpu.arch == .wasm32 or target.result.cpu.arch == .wasm64) {
        try wasm_build.build(b, target, optimize);
    } else {
        try exe_build.build(b, target, optimize);
    }
}
