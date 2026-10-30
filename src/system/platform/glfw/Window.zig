const Window = @This();

height: u32,
width: u32,

window: *c.GLFWwindow,
event_queue: *root.EventQueue,

pub fn nextEvent(self: *Window) ?root.Event {
    return self.event_queue.pop();
}

pub fn destroy(self: Window, allocator: Allocator) void {
    allocator.destroy(self.event_queue);
}

pub fn create(allocator: Allocator, options: root.WindowOptions) !Window {
    const event_queue = try allocator.create(root.EventQueue);
    errdefer allocator.destroy(event_queue);

    event_queue.* = .empty;

    if (@import("builtin").mode == .debug)
        _ = c.glfwSetErrorCallback(callbacks.errorCallback);

    _ = c.glfwInit();

    // if (render_backend != .opengl)
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    const title = try allocator.allocSentinel(u8, options.title.len, 0);
    defer allocator.free(title);
    @memcpy(title, options.title);

    const glfw_window = c.glfwCreateWindow(
        @intCast(options.width),
        @intCast(options.height),
        title.ptr,
        null,
        null,
    ) orelse return error.GLFWCreateWindow;

    var fb_w: c_int = 0;
    var fb_h: c_int = 0;
    c.glfwGetFramebufferSize(glfw_window, &fb_w, &fb_h);

    _ = c.glfwSetWindowUserPointer(glfw_window, event_queue);
    _ = c.glfwSetFramebufferSizeCallback(glfw_window, callbacks.framebufferSize);
    _ = c.glfwSetWindowCloseCallback(glfw_window, callbacks.windowClose);
    _ = c.glfwSetKeyCallback(glfw_window, callbacks.key);
    _ = c.glfwSetCharCallback(glfw_window, callbacks.char);
    _ = c.glfwSetScrollCallback(glfw_window, callbacks.scroll);
    _ = c.glfwSetWindowIconifyCallback(glfw_window, callbacks.iconify);
    _ = c.glfwSetMouseButtonCallback(glfw_window, callbacks.mouseButton);
    _ = c.glfwSetCursorPosCallback(glfw_window, callbacks.cursorPos);

    c.glfwShowWindow(glfw_window);

    // if (render_backend == .opengl)
    //     c.glfwMakeContextCurrent(self.window);

    return .{
        .window = glfw_window,
        .event_queue = event_queue,
        .width = @intCast(fb_w),
        .height = @intCast(fb_h),
    };
}

pub fn setTitle(self: *Window, title: []const u8) !void {
    const title_z = try std.heap.c_allocator.allocSentinel(u8, title.len, 0);
    defer std.heap.c_allocator.free(title_z);
    @memcpy(title_z, title);
    c.glfwSetWindowTitle(self.window, title_z);
}

pub fn poll(self: *Window) void {
    var counter: usize = 0;
    while (counter < root.EventQueue.limit) : (counter += 1) {
        c.glfwPollEvents();
    }

    var width: c_int = 0;
    var height: c_int = 0;
    c.glfwGetFramebufferSize(self.window, &width, &height);
    self.width = @intCast(width);
    self.height = @intCast(height);
}

pub fn close(_: *Window) void {
    c.glfwTerminate();
}

pub fn getHandles(self: *const Window) root.WindowHandles {
    return .{
        .window = self.window,
    };
}

pub fn requistAttention(self: *const Window) void {
    _ = c.glfwRequestWindowAttention(self.window);
}

fn hasEnv(name: []const u8) bool {
    var i: usize = 0;
    while (std.c.environ[i]) |entry| : (i += 1) {
        const key = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(entry)), '=');
        if (std.mem.eql(u8, key, name)) return true;
    }
    return false;
}

const callbacks = struct {
    fn eventQueue(glfw_window: ?*c.GLFWwindow) ?*root.EventQueue {
        return @ptrCast(@alignCast(c.glfwGetWindowUserPointer(glfw_window) orelse return null));
    }

    fn key(glfw_window: ?*c.GLFWwindow, key_: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;

        if (key_ == c.GLFW_KEY_ESCAPE) {
            queue.push(.close) catch unreachable;
            return;
        }

        const event = root.Event{
            .input = .{
                .keyboard = .{
                    .type = if (action == c.GLFW_PRESS)
                        .press
                    else if (action == c.GLFW_REPEAT)
                        .repeat
                    else
                        .release,
                    .key = keyboard.keyFromGlfw(key_),
                    .code = @intCast(scancode),

                    .mods = .{
                        // zig fmt: off
                        .shift = (mods & c.GLFW_MOD_SHIFT)     != 0,
                        .ctrl  = (mods & c.GLFW_MOD_CONTROL)   != 0,
                        .alt   = (mods & c.GLFW_MOD_ALT)       != 0,
                        .super = (mods & c.GLFW_MOD_SUPER)     != 0,
                        .caps  = (mods & c.GLFW_MOD_CAPS_LOCK) != 0,
                        .num   = (mods & c.GLFW_MOD_NUM_LOCK)  != 0,
                        // zig fmt: on
                    },
                },
            },
        };

        queue.push(event) catch unreachable;
    }

    fn char(glfw_window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;

        const event = root.Event{
            .input = .{
                .utf8_codepoint = @intCast(codepoint),
            },
        };

        queue.push(event) catch unreachable;
    }

    fn scroll(glfw_window: ?*c.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;

        const event = root.Event{ .input = .{
            .mouse = .{ .scroll = .{
                .x_offset = @floatCast(xoffset),
                .y_offset = @floatCast(yoffset),
            } },
        } };

        queue.push(event) catch unreachable;
    }

    fn framebufferSize(glfw_window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;

        const event = root.Event{
            .resize = .{
                .height = @intCast(height),
                .width = @intCast(width),

                .is_live = false,
            },
        };

        queue.push(event) catch unreachable;
    }

    fn mouseButton(glfw_window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;

        _ = mods;

        const event = root.Event{
            .input = .{
                .mouse = .{
                    .button = .{
                        // mouse input enum matches the glfw mouse buttons enumeration
                        .button = @fromBackingInt(@intCast(button)),
                        .state = if (action == c.GLFW_PRESS) .press else .release,
                    },
                },
            },
        };

        queue.push(event) catch unreachable;
    }

    fn cursorPos(glfw_window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;

        const new_x: f32 = @floatCast(xpos);
        const new_y: f32 = @floatCast(ypos);

        var new_dx: f32 = 0;
        var new_dy: f32 = 0;

        if (queue.popLast()) |last_event| {
            if (last_event == .input and last_event.input == .mouse and
                last_event.input.mouse == .move)
            {
                new_dx = last_event.input.mouse.move.dx + new_x -
                    last_event.input.mouse.move.x;
                new_dy = last_event.input.mouse.move.dy + new_y -
                    last_event.input.mouse.move.y;
            } else {
                queue.push(last_event) catch unreachable;
            }
        }

        const event = root.Event{
            .input = .{ .mouse = .{ .move = .{
                .x = new_x,
                .y = new_y,
                .dx = new_dx,
                .dy = new_dy,
            } } },
        };

        queue.push(event) catch unreachable;
    }

    fn windowClose(glfw_window: ?*c.GLFWwindow) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;
        queue.push(.close) catch unreachable;
    }

    fn iconify(glfw_window: ?*c.GLFWwindow, iconified: c_int) callconv(.c) void {
        const queue = eventQueue(glfw_window) orelse return;
        queue.push(.{ .expose = iconified == c.GLFW_TRUE }) catch unreachable;
    }

    fn errorCallback(code: c_int, description: [*c]const u8) callconv(.c) void {
        std.log.scoped(.glfw).err(": {} {s}", .{ code, description });
    }
};

const std = @import("std");

const root = @import("zerotty").system.platform;
const keyboard = @import("zerotty").system.input.keyboard;
const c = @import("c_glfw");

const Allocator = std.mem.Allocator;
