pub const MouseButton = enum(u8) {
    left,
    right,
    middle,
    button_4,
    button_5,
    _,
};

pub const ButtonState = enum {
    press,
    release,
};

pub const MouseButtonEvent = struct {
    button: MouseButton,
    state: ButtonState,
};

pub const MouseMoveEvent = struct {
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
};

pub const MouseScrollEvent = struct {
    x_offset: f32,
    y_offset: f32,
};

pub const MouseEvent = union(enum) {
    button: MouseButtonEvent,
    scroll: MouseScrollEvent,
    move: MouseMoveEvent,
};
