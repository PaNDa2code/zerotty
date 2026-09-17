const App = @This();

config: Config,

io: std.Io,
allocator: std.mem.Allocator,

io_event_loop: myio.EventLoop,

platform: Platform,
renderer: Renderer,

buf: []u8,
terminal: *Terminal,

cell_width: u32,
cell_height: u32,

font_ttf: font.Font,
font_data: []const u8,

pending_font_size: ?u32 = null,

/// CPU-side mirror of the per-cell background color texture
/// (rows * cols * 4 RGBA8 bytes). Refreshed every frame, mirroring
/// the per-frame regeneration of the text instance list.
bg_color_data: std.ArrayList(u8) = .empty,

const min_font_size: u32 = 20;
const max_font_size: u32 = 96;
const font_size_step: u32 = 10;

fn bellAction(_app: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(_app));
    app.platform.current_window.?.requistAttention();
}

pub fn init(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *std.process.Environ.Map,
) !App {
    AssetsManager.instance =
        if (builtin.mode == .ReleaseSmall)
            try .decompressAndInit(
                allocator,
                AssetsManager.assets_archive,
            )
        else
            .initFromTar(
                AssetsManager.assets_tar,
            );

    const config = zerotty.config.getConfig(io, environ_map, allocator) catch
        Config{};

    const font_asset = try AssetsManager.instance
        .get("fonts/JetBrainsMono/ttf/JetBrainsMono-Regular.ttf");
    const font_data = try font_asset.fixedBuffer();

    var font_ttf = try font.Font.init(font_data, @intCast(config.font_size));

    const metrics = font_ttf.cellMetrics();
    const cell_width: u32 = metrics.cell_width;
    const cell_height: u32 = metrics.cell_height;

    var platform = Platform.init(allocator);

    const initial_width = 800;
    const initial_height = 600;

    _ = try platform.createWindow(.{
        .title = "zerotty",
        .height = initial_height,
        .width = initial_width,
    });

    const initial_cols = initial_width / cell_width;
    const initial_rows = initial_height / cell_height;

    const renderer = try Renderer.init(
        allocator,
        try platform.getWindowNativeHandles(),
        .{},
        .{
            .surface_height = initial_height,
            .surface_width = initial_width,
            .grid_rows = initial_rows,
            .grid_cols = initial_cols,
            .cell_width = cell_width,
            .cell_height = cell_height,
            .baseline = metrics.baseline,
        },
    );

    const terminal = try allocator.create(Terminal);

    var event_loop = try myio.EventLoop.init(allocator, 100);

    terminal.* = try Terminal.init(
        io,
        environ_map,
        allocator,
        if (os_tag == .linux) .{
            .shell_path = "/bin/bash",
            .shell_args = &.{ "bash", "--norc", "--noprofile" },
            .rows = initial_rows,
            .cols = initial_cols,
        } else if (os_tag == .windows) .{
            .shell_path = "cmd.exe",
            .shell_args = &.{"cmd"},
            .rows = initial_rows,
            .cols = initial_cols,
        },
    );

    const buf = try allocator.alloc(u8, 1024);
    try event_loop.read(terminal.pty.readFile(), buf, ptyReadCallback, terminal);

    return .{
        .config = config,

        .io = io,
        .allocator = allocator,

        .platform = platform,
        .renderer = renderer,

        .io_event_loop = event_loop,

        .buf = buf,
        .terminal = terminal,

        .cell_width = cell_width,
        .cell_height = cell_height,

        .font_ttf = font_ttf,
        .font_data = font_data,
    };
}

fn applyFontSize(
    self: *App,
    font_ttf: *font.Font,
    cache: *font.Cache,
    font_data: []const u8,
    new_size: u32,
) !void {
    font_ttf.deinit();
    font_ttf.* = try font.Font.init(font_data, @intCast(new_size));

    cache.deinit();
    cache.* = font.Cache.init(self.allocator);

    try self.renderer.resetGlyphCache();

    self.config.font_size = new_size;

    const metrics = font_ttf.cellMetrics();
    self.cell_width = metrics.cell_width;
    self.cell_height = metrics.cell_height;

    self.renderer.settings.cell_width = self.cell_width;
    self.renderer.settings.cell_height = self.cell_height;
    self.renderer.settings.baseline = metrics.baseline;

    const window = self.platform.current_window.?;
    const cols = @max(1, window.width / self.cell_width);
    const rows = @max(1, window.height / self.cell_height);

    try self.terminal.pty.resize(.{
        .width = @intCast(cols),
        .height = @intCast(rows),
    });
    try self.terminal.grid.resizeVisable(self.allocator, rows, cols);
    try self.renderer.setGridSize(@intCast(cols), @intCast(rows));
}

pub fn run(self: *App) !void {
    self.terminal.bell_action_data = self;
    self.terminal.bell_action_callback = bellAction;

    self.terminal.vtparser.user_data = self.terminal;

    var running = true;

    var frame_tik = std.Io.Timestamp.zero;
    var frames: usize = 0;

    var cursor_tik = std.Io.Timestamp.zero;

    var cache = font.Cache.init(self.allocator);
    defer cache.deinit();

    while (running) {
        try self.platform.pollEvents();
        const events_queue = self.platform.eventQueue();

        try self.io_event_loop.poll(0);

        const shell_exit =
            try self.terminal.shell.wait(false);

        if (shell_exit == .ended) break;

        while (events_queue.pop()) |event| {
            std.log.debug("event: {any}", .{event});

            switch (event) {
                .close => {
                    running = false;
                    break;
                },
                .resize => |size| {
                    try self.renderer.resizeSurface(
                        size.width,
                        size.height,
                    );
                    const cols = @max(1, size.width / self.cell_width);
                    const rows = @max(1, size.height / self.cell_height);

                    try self.terminal.pty.resize(
                        .{
                            .width = @intCast(cols),
                            .height = @intCast(rows),
                        },
                    );

                    try self.terminal.grid.resizeVisable(self.allocator, rows, cols);
                    try self.renderer.setGridSize(@intCast(cols), @intCast(rows));
                },
                .input => |input_event| {
                    var sink = self.inputSink();
                    try InputHandler.handle(&sink.sink, self.io, input_event);

                    if (self.pending_font_size) |new_size| {
                        self.pending_font_size = null;
                        if (new_size != self.config.font_size)
                            try self.applyFontSize(&self.font_ttf, &cache, self.font_data, new_size);
                    }

                    self.terminal.grid.show_cursor = true;
                    cursor_tik = .now(self.io, .real);
                },
                else => {},
            }
        }

        var instance_list: std.ArrayList(TextInstance) = .empty;
        defer instance_list.deinit(self.allocator);

        var pixels_pool: std.ArrayList(u8) = .empty;
        defer pixels_pool.deinit(self.allocator);

        const grid_cols = self.terminal.grid.rows_width;
        const grid_rows = self.terminal.grid.visable_rows;
        const bg_bytes = grid_cols * grid_rows * 4;

        if (self.bg_color_data.items.len != bg_bytes) {
            self.bg_color_data.clearRetainingCapacity();
            try self.bg_color_data.resize(self.allocator, bg_bytes);
        }

        var grid_iter = self.terminal.grid.iterator();

        while (grid_iter.next()) |item| {
            if (item.cell.unicode == 0 or item.cell.unicode == ' ')
                continue;

            const glyph_id = font.GlyphID{
                .font = @enumFromInt(0),
                .index = @enumFromInt(item.cell.unicode),
            };
            const glyph_entry =
                cache.getAtlasEntry(glyph_id) orelse blk: {
                    const index = self.font_ttf.ttf.codepointGlyphIndex(@intCast(item.cell.unicode));
                    const bmp = try self.font_ttf.ttf.glyphBitmap(
                        self.allocator,
                        &pixels_pool,
                        index,
                        self.font_ttf.scale_x,
                        self.font_ttf.scale_y,
                    );

                    // const current_len = pixels_pool.items.len;
                    // const align_len = std.mem.alignForward(usize, current_len, 16);
                    //
                    // if (current_len < align_len)
                    //     try pixels_pool.appendNTimes(self.allocator, 0, align_len - current_len);

                    var new_atlas: bool = false;

                    break :blk try cache.pushEntry(
                        glyph_id,
                        @intCast(bmp.width),
                        @intCast(bmp.height),
                        @intCast(bmp.off_x),
                        @intCast(bmp.off_y),
                        &new_atlas,
                    );
                };
            try instance_list.append(self.allocator, .{
                .p_postion = (@as(u32, @intCast(item.y)) & 0xFFFF) | (@as(u32, @intCast(item.x)) << 16),
                .p_glyph_entry = @bitCast(glyph_entry),
                .fg_color = item.cell.fg_color,
                .bg_color = item.cell.bg_color,
            });
        }

        self.terminal.grid.fillBackgroundColors(self.bg_color_data.items);

        try self.renderer.beginFrame();

        try self.renderer.setViewport(
            0,
            0,
            self.platform.current_window.?.width,
            self.platform.current_window.?.height,
        );

        self.renderer.clear(.black);

        if (cache.new_added_entries.items.len > 0) {
            try self.renderer.cacheGlyphs(
                cache.new_added_entries.items,
                pixels_pool.items,
            );

            cache.new_added_entries.clearRetainingCapacity();
        }

        try self.renderer.uploadBackground(
            @intCast(grid_rows),
            @intCast(grid_cols),
            self.bg_color_data.items,
        );

        if (instance_list.items.len != 0) {
            const batch = try self.renderer.reserveBatch(instance_list.items.len);
            @memcpy(batch, instance_list.items);

            try self.renderer.commitBatch(instance_list.items.len);
        }

        try self.renderer.endFrame();
        try self.renderer.presnt();

        frames += 1;

        const frame_diff = frame_tik.untilNow(self.io, .real);

        if (frame_diff.nanoseconds >= std.time.ns_per_s) {
            const secands = @as(f64, @floatFromInt(frame_diff.nanoseconds)) * (1.0 / @as(comptime_float, std.time.ns_per_s));
            const fps = @as(f64, @floatFromInt(frames)) / secands;

            var buf: [255]u8 = undefined;
            const title = try std.fmt.bufPrintZ(&buf, "zerotty - FPS: {:.02}", .{fps});
            try self.platform.current_window.?.setTitle(title);

            frames = 0;
            frame_tik = .now(self.io, .real);
        }

        const cursor_diff = cursor_tik.untilNow(self.io, .real);

        if (cursor_diff.nanoseconds >= std.time.ns_per_s) {
            self.terminal.grid.show_cursor = !self.terminal.grid.show_cursor;
            cursor_tik = .now(self.io, .real);
        }
    }
}

pub fn deinit(self: *App) void {
    self.renderer.deinit();
    self.platform.deinit();
    self.terminal.deinit(self.allocator);
    self.allocator.free(self.buf);
    self.io_event_loop.deinit(self.allocator);

    self.allocator.destroy(self.terminal);

    AssetsManager.instance.deinit();
}

/// Build an `InputHandler.Sink` that writes to our PTY and drives the grid.
/// The returned Sink MUST be used synchronously in the same stack frame.
fn inputSink(self: *App) AppSink {
    return .{
        .app = self,
        .sink = .{
            .writeFn = AppSink.write,
            .scrollUpFn = AppSink.scrollUp,
            .scrollDownFn = AppSink.scrollDown,
            .scrollToBottomFn = AppSink.scrollToBottom,
            .pasteFn = AppSink.paste,
            .fontSizeFn = AppSink.changeFontSize,
        },
    };
}

/// Concrete `InputHandler.Sink` implementation backed by an `App` pointer.
const AppSink = struct {
    sink: InputHandler.Sink,
    app: *App,

    fn write(sink: *InputHandler.Sink, io: std.Io, data: []const u8) anyerror!void {
        const self: *AppSink = @fieldParentPtr("sink", sink);
        try self.app.terminal.shell.stdin.?.writeStreamingAll(io, data);
    }
    fn scrollUp(sink: *InputHandler.Sink, lines: u32) void {
        const self: *AppSink = @fieldParentPtr("sink", sink);
        self.app.terminal.grid.scrollUp(lines);
    }
    fn scrollDown(sink: *InputHandler.Sink, lines: u32) void {
        const self: *AppSink = @fieldParentPtr("sink", sink);
        self.app.terminal.grid.scrollDown(lines);
    }
    fn scrollToBottom(sink: *InputHandler.Sink) void {
        const self: *AppSink = @fieldParentPtr("sink", sink);
        self.app.terminal.grid.scrollToBottom();
    }
    fn paste(sink: *InputHandler.Sink, io: std.Io) anyerror!void {
        const self: *AppSink = @fieldParentPtr("sink", sink);
        const str = self.app.platform.clipboard.getString();
        try self.app.terminal.shell.stdin.?.writeStreamingAll(io, str);
    }
    fn changeFontSize(sink: *InputHandler.Sink, delta: i32) void {
        const self: *AppSink = @fieldParentPtr("sink", sink);
        const current = self.app.config.font_size;
        const new_size =
            if (delta > 0)
                @min(current + font_size_step, max_font_size)
            else
                @max(current - font_size_step, min_font_size);
        self.app.pending_font_size = new_size;
    }
};

fn ptyReadCallback(event: *myio.EventLoop.Event, len: usize, user_data: ?*anyopaque) myio.EventLoop.CallbackAction {
    const buffer = event.request.op_data.read[0..len];
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));
    terminal.vtparser.parse(buffer);
    return .retry;
}

const std = @import("std");
const builtin = @import("builtin");
const zerotty = @import("zerotty");

const myio = zerotty.system.io;
const Platform = zerotty.system.platform.Platform;
const font = zerotty.font;
const Terminal = zerotty.terminal.Terminal;
const AssetsManager = zerotty.AssetsManager;
const TextInstance = zerotty.renderer.vertex.TextInstance;
const color = zerotty.terminal.color;
const Renderer = zerotty.renderer.Renderer;
const InputHandler = @import("InputHandler.zig");

const os_tag = builtin.os.tag;

const Config = zerotty.config.Config;
