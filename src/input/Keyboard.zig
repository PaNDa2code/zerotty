const Keyboard = @This();

pub const keyboard_key_count = 256;
// Can be stored in AVX register (YMMx)
pub const KeyboardState = std.bit_set.IntegerBitSet(keyboard_key_count);

pub const KeyEventType = enum {
    press,
    release,
    repeat,
};

pub const KeyEvent = struct {
    type: KeyEventType = .press,
    state: KeyboardState,
    code: u8,
};

const KeyboardEventQueue = std.ArrayList(KeyEvent);

allocator: Allocator,
event_queue: KeyboardEventQueue,
state: KeyboardState,
auto_repeat_enabled: bool,

pub fn init(allocator: Allocator) Keyboard {
    return .{
        .allocator = allocator,
        .event_queue = .empty,
        .state = KeyboardState.initEmpty(),
        .auto_repeat_enabled = false,
    };
}

pub fn deinit(self: *Keyboard) void {
    self.event_queue.deinit(self.allocator);
}

pub fn pushEvent(self: *Keyboard, event: KeyEvent) !void {
    try self.event_queue.append(self.allocator, event);
    switch (event.type) {
        .press => self.state.set(event.code),
        .release => self.state.unset(event.code),
        .repeat => {},
    }
}

pub fn popEvent(self: *Keyboard) ?KeyEvent {
    return self.event_queue.pop();
}

pub fn keyIsPressed(self: *Keyboard, key_code: u8) bool {
    return self.state.isSet(key_code);
}

const shortcuts: []const KeyboardState = {};


const std = @import("std");

const Allocator = std.mem.Allocator;
