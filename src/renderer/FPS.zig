const FPS = @This();

timer: std.time.Timer,
frames: u64 = 0,
fps: f64 = 0,

const FPSInitError = std.time.Timer.Error;

pub fn init() FPSInitError!FPS {
    return .{
        .timer = try std.time.Timer.start(),
    };
}

pub fn frame(self: *FPS) void {
    self.frames += 1;
}

pub fn calculate(self: *FPS) void {
    const time_ns = self.timer.lap();
    const time_s: f64 = @as(f64, @floatFromInt(time_ns)) / std.time.ns_per_s;
    self.fps = @as(f64, @floatFromInt(self.frames)) / time_s;
    self.frames = 0;
}

pub fn getFps(self: *FPS) f64 {
    self.frame();
    if (self.timer.read() >= std.time.ns_per_s) {
        self.calculate();
    }
    return self.fps;
}

const std = @import("std");
