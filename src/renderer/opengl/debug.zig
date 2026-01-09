const log = std.log.scoped(.OpenGL);

pub fn openglDebugCallback(
    source: gl.@"enum",
    @"type": gl.@"enum",
    _: gl.uint,
    severity: gl.@"enum",
    _: gl.sizei,
    message: [*:0]const u8,
    _: ?*const anyopaque,
) callconv(gl.APIENTRY) void {
    log.debug("({s},{s},{s}): {s}", .{
        @tagName(@as(DebugType, @enumFromInt(@"type"))),
        @tagName(@as(DebugSource, @enumFromInt(source))),
        @tagName(@as(DebugSeverity, @enumFromInt(severity))),
        message,
    });
}

const DebugType = enum(u32) {
    deprecated_behavior = 0x824d,
    @"error" = 0x824c,
    marker = 0x8268,
    other = 0x8251,
    performance = 0x8250,
    pop_group = 0x826a,
    portability = 0x824f,
    push_group = 0x8269,
    undefined_behavior = 0x824e,
};

const DebugSeverity = enum(u32) {
    high = 0x9146,
    low = 0x9148,
    medium = 0x9147,
    notification = 0x826b,
};

const DebugSource = enum(u32) {
    api = 0x8246,
    application = 0x824a,
    other = 0x824b,
    shader_compiler = 0x8248,
    third_party = 0x8249,
    window_system = 0x8247,
};

const std = @import("std");
const gl = @import("gl");
