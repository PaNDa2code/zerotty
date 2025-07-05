const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");
const build_options = @import("build_options");

const os = builtin.os.tag;
const Allocator = std.mem.Allocator;

pub const Window = switch (build_options.@"window-system") {
    .Win32 => Win32Window,
    .Xlib => XlibWindow,
    .Xcb => XcbWindow,
};

pub const WindowResizeEvent = struct {
    new_height: u32,
    new_width: u32,
};

const Win32Window = struct {
    pub const system = .Win32;

    const win32fnd = win32.foundation;
    const win32wm = win32.ui.windows_and_messaging;
    const win32dwm = win32.graphics.dwm;
    const win32loader = win32.system.library_loader;

    const HANDLE = win32fnd.HANDLE;
    const HINSTANCE = win32fnd.HINSTANCE;
    const HWND = win32fnd.HWND;
    const LRESULT = win32fnd.LRESULT;
    const WPARAM = win32fnd.WPARAM;
    const LPARAM = win32fnd.LPARAM;

    const RendererApi = @import("renderer/root.zig").Renderer;

    exit: bool = false,
    hwnd: HWND = undefined,
    h_instance: HINSTANCE = undefined,
    title: []const u8,
    height: u32,
    width: u32,
    renderer: RendererApi = undefined,

    pub fn new(title: []const u8, height: u32, width: u32) Window {
        return .{
            .title = title,
            .height = height,
            .width = width,
        };
    }

    pub fn open(self: *Window, allocator: Allocator) !void {
        const class_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, self.title);
        defer allocator.free(class_name);

        self.h_instance = win32loader.GetModuleHandleW(null) orelse unreachable;

        var window_class = std.mem.zeroes(win32wm.WNDCLASSW);
        window_class.lpszClassName = class_name;
        window_class.hInstance = self.h_instance;
        window_class.lpfnWndProc = &WindowProcSetup;
        window_class.style = .{ .OWNDC = 1, .VREDRAW = 1, .HREDRAW = 1 };

        window_class.hIcon = win32wm.LoadIconW(self.h_instance, std.unicode.utf8ToUtf16LeStringLiteral("APP_LOGO"));

        _ = win32wm.RegisterClassW(&window_class);

        const window_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, self.title);
        defer allocator.free(window_name);

        const hwnd = win32wm.CreateWindowExW(
            .{},
            class_name,
            window_name,
            win32wm.WS_OVERLAPPEDWINDOW,
            win32wm.CW_USEDEFAULT,
            win32wm.CW_USEDEFAULT,
            @bitCast(self.width),
            @bitCast(self.height),
            null,
            null,
            window_class.hInstance,
            self,
        ) orelse return error.CreateWindowFailed;

        // const menu = win32wm.CreateMenu() orelse return error.CreateMenuFailed;
        // const menu_bar = win32wm.CreateMenu() orelse return error.CreateMenuFailed;
        // _ = win32wm.AppendMenuW(menu, win32wm.MF_STRING, 1, std.unicode.utf8ToUtf16LeStringLiteral("&New"));
        // _ = win32wm.AppendMenuW(menu, win32wm.MF_STRING, 2, std.unicode.utf8ToUtf16LeStringLiteral("&Close"));
        // _ = win32wm.AppendMenuW(menu_bar, win32wm.MF_POPUP, @intFromPtr(menu), std.unicode.utf8ToUtf16LeStringLiteral("&File"));
        // _ = win32wm.SetMenu(hwnd, menu_bar);

        _ = win32.ui.hi_dpi.SetProcessDpiAwareness(.PER_MONITOR_DPI_AWARE);

        const darkmode: u32 = 1;

        _ = win32dwm.DwmSetWindowAttribute(
            hwnd,
            win32dwm.DWMWA_USE_IMMERSIVE_DARK_MODE,
            &darkmode,
            @sizeOf(u32),
        );

        self.hwnd = hwnd;

        self.renderer = try RendererApi.init(self, allocator);

        _ = win32wm.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    }

    pub fn close(self: *Window) void {
        self.renderer.deinit();
    }

    pub fn resize(self: *Window, height: u32, width: u32) !void {
        self.height = height;
        self.width = width;
        // self.renderer.resize(width, height);
    }

    fn WindowProcSetup(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        if (msg != win32wm.WM_NCCREATE) {
            return win32wm.DefWindowProcW(hwnd, msg, wparam, lparam);
        }
        const p_create: *const win32wm.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        const self: *Window = @ptrCast(@alignCast(p_create.lpCreateParams));

        _ = win32wm.SetWindowLongPtrW(hwnd, .P_USERDATA, @bitCast(@intFromPtr(self)));
        _ = win32wm.SetWindowLongPtrW(hwnd, .P_WNDPROC, @bitCast(@intFromPtr(&WindowProcWrapper)));

        return self.WindowProc(hwnd, msg, wparam, lparam);
    }
    fn WindowProcWrapper(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        const self: *Window = @ptrFromInt(@as(usize, @bitCast(win32wm.GetWindowLongPtrW(hwnd, .P_USERDATA))));
        return self.WindowProc(hwnd, msg, wparam, lparam);
    }
    fn WindowProc(self: *Window, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) LRESULT {
        switch (msg) {
            win32wm.WM_DESTROY => {
                self.exit = true;
                win32wm.PostQuitMessage(0);
                return 0;
            },
            win32wm.WM_KEYDOWN, win32wm.WM_SYSKEYDOWN => {
                if (wparam == @intFromEnum(win32.ui.input.keyboard_and_mouse.VK_ESCAPE)) {
                    win32wm.PostQuitMessage(0);
                }
                return 0;
            },
            win32wm.WM_PAINT => {
                return 0;
            },
            win32wm.WM_SIZING => {
                return 0;
            },
            win32wm.WM_ENTERSIZEMOVE => {
                return win32wm.SendMessageW(hwnd, win32wm.WM_SETREDRAW, 0, 0);
            },
            win32wm.WM_EXITSIZEMOVE => {
                return win32wm.SendMessageW(hwnd, win32wm.WM_SETREDRAW, 1, 0);
            },
            win32wm.WM_ERASEBKGND => {
                return 0;
            },
            win32wm.WM_SIZE => {
                const lp: usize = @as(usize, @bitCast(lparam));
                const width: u32 = @intCast(lp & 0xFFFF);
                const height: u32 = @intCast((lp >> 16) & 0xFFFF);
                self.resize(height, width) catch return -1;
                return 0;
            },
            else => return win32wm.DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    pub fn messageLoop(self: *Window) void {
        while (!self.exit) {
            self.pumpMessages();
        }
    }

    pub fn pumpMessages(self: *Window) void {
        var msg: win32wm.MSG = undefined;

        while (win32wm.PeekMessageW(&msg, null, 0, 0, .{ .REMOVE = 1 }) != 0) {
            if (msg.message == win32wm.WM_QUIT) {
                self.exit = true;
                return;
            }

            _ = win32wm.TranslateMessage(&msg);
            _ = win32wm.DispatchMessageW(&msg);
        }
    }
};

const XlibWindow = struct {
    pub const system = .Xlib;

    const x11 = @cImport({
        @cInclude("X11/Xlib.h");
        @cInclude("X11/keysym.h");
    });

    const RendererApi = @import("renderer/root.zig").Renderer;

    socket: i32 = undefined,
    title: []const u8,
    height: u32,
    width: u32,
    display: *x11.Display = undefined,
    s: c_int = undefined,
    w: c_ulong = undefined,
    renderer: RendererApi = undefined,

    exit: bool = false,
    wm_delete_window: c_ulong = 0,

    pub fn new(title: []const u8, height: u32, width: u32) Window {
        return .{
            .title = title,
            .height = height,
            .width = width,
        };
    }

    pub fn open(self: *Window, allocator: Allocator) !void {
        const display = x11.XOpenDisplay(null);
        const screen = x11.DefaultScreen(display);

        self.display = display.?;
        self.s = screen;

        // x11 window is created inside opengl context creator
        self.renderer = try RendererApi.init(self, allocator);

        const name = try std.fmt.allocPrintZ(allocator, "{s}", .{self.title});
        _ = x11.XStoreName(@ptrCast(display), self.w, name.ptr);
        allocator.free(name);

        var wm_delete_window = x11.XInternAtom(@ptrCast(self.display), "WM_DELETE_WINDOW", 0);
        _ = x11.XSetWMProtocols(@ptrCast(self.display), self.w, &wm_delete_window, 1);

        self.wm_delete_window = wm_delete_window;
    }

    pub fn messageLoop(self: *Window) void {
        while (!self.exit) {
            self.pumpMessages();
        }
    }

    pub fn pumpMessages(self: *Window) void {
        var event: x11.XEvent = undefined;
        const pending = x11.XPending(self.display);
        var i: c_int = 0;
        while (i < pending) : (i += 1) {
            _ = x11.XNextEvent(self.display, &event);

            if (event.type == x11.KeyPress and
                x11.XLookupKeysym(@constCast(&event.xkey), 0) == x11.XK_Escape)
            {
                self.exit = true;
                break;
            }

            if (event.type == x11.ClientMessage and
                event.xclient.data.l[0] == self.wm_delete_window)
            {
                self.exit = true;
                break;
            }
        }
    }

    pub fn close(self: *Window) void {
        self.renderer.deinit();
        _ = x11.XDestroyWindow(@ptrCast(self.display), self.w);
        _ = x11.XCloseDisplay(@ptrCast(self.display));
    }
};

const XcbWindow = struct {
    pub const system = .Xcb;

    const c = @cImport({
        @cInclude("xcb/xcb.h");
        @cInclude("X11/keysym.h");
    });

    const RendererApi = @import("renderer/root.zig").Renderer;

    connection: *c.xcb_connection_t = undefined,
    screen: *c.xcb_screen_t = undefined,
    window: c.xcb_window_t = undefined,
    renderer: RendererApi = undefined,

    exit: bool = false,
    title: []const u8,
    height: u32,
    width: u32,

    pub fn new(title: []const u8, height: u32, width: u32) Window {
        return .{
            .title = title,
            .height = height,
            .width = width,
        };
    }

    pub fn open(self: *Window, allocator: Allocator) !void {
        self.connection = c.xcb_connect(null, null).?;
        if (c.xcb_connection_has_error(self.connection) != 0) {
            return error.XCBConnectionError;
        }

        const setup = c.xcb_get_setup(self.connection);
        self.screen = c.xcb_setup_roots_iterator(setup).data.?;

        const window_id = c.xcb_generate_id(self.connection);
        self.window = window_id;

        const value_mask: u32 = c.XCB_CW_BACK_PIXEL | c.XCB_CW_EVENT_MASK;
        const value_list = [_]u32{
            self.screen.*.white_pixel,
            c.XCB_EVENT_MASK_EXPOSURE |
                c.XCB_EVENT_MASK_KEY_PRESS |
                c.XCB_EVENT_MASK_STRUCTURE_NOTIFY,
        };

        _ = c.xcb_create_window(
            self.connection,
            self.screen.*.root_depth, // depth
            window_id, // window id
            self.screen.*.root, // parent window
            0,
            0, // x, y
            800,
            600, // width, height
            0, // border width
            c.XCB_WINDOW_CLASS_INPUT_OUTPUT,
            self.screen.*.root_visual,
            value_mask,
            &value_list,
        );

        // Set window title
        const title = try allocator.dupeZ(u8, self.title);
        defer allocator.free(title);
        _ = c.xcb_change_property(
            self.connection,
            c.XCB_PROP_MODE_REPLACE,
            window_id,
            c.XCB_ATOM_WM_NAME,
            c.XCB_ATOM_STRING,
            8,
            @intCast(title.len),
            title.ptr,
        );

        // Map (show) the window
        _ = c.xcb_map_window(self.connection, window_id);

        // Flush all commands
        _ = c.xcb_flush(self.connection);

        self.renderer = try RendererApi.init(self, allocator);
    }

    pub fn pumpMessages(self: *Window) void {
        while (c.xcb_poll_for_event(self.connection)) |event| {
            const response_type = event.*.response_type & 0x7F;

            switch (response_type) {
                c.XCB_EXPOSE => {},
                c.XCB_KEY_PRESS => {
                    const key_press: *c.xcb_key_press_event_t = @ptrCast(event);
                    if (key_press.detail == 9)
                        self.exit = true;
                },
                c.XCB_DESTROY_NOTIFY => {
                    self.exit = true;
                },
                c.XCB_CLIENT_MESSAGE => {},
                else => {},
            }

            // Free the event after processing
            std.c.free(event);
        }
    }
    pub fn close(self: *Window) void {
        _ = c.xcb_destroy_window(self.connection, self.window);
        c.xcb_disconnect(self.connection);
        self.renderer.deinit();
    }
};
