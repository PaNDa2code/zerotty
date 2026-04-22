const App = @This();

allocator: std.mem.Allocator,

window: *win.Window,
renderer: Renderer,
io_event_loop: io.EventLoop,

buf: []u8,
terminal: *Terminal,

pub fn init(allocator: std.mem.Allocator) !App {
    const window = try win.Window.initAlloc(allocator, .{
        .title = "zerotty",
        .height = 600,
        .width = 800,
    });

    const renderer = try Renderer.init(allocator, window.getHandles(), .{
        .surface_width = window.w.width,
        .surface_height = window.w.height,
        .grid_rows = 100,
        .grid_cols = 100,
    });

    var io_event_loop = try io.EventLoop.init(allocator, 100);

    const terminal = try allocator.create(Terminal);

    AssetsManager.instance = try AssetsManager.init(
        allocator,
        AssetsManager.assets_archive,
    );

    terminal.* = try Terminal.init(allocator, if (os_tag == .linux) .{
        .shell_path = "/bin/bash",
        .shell_args = &.{ "bash", "--norc", "--noprofile" },
        .rows = 100,
        .cols = 100,
    } else if (os_tag == .windows) .{
        .shell_path = "cmd.exe",
        .shell_args = &.{"cmd"},
        .rows = 100,
        .cols = 100,
    });

    const buf = try allocator.alloc(u8, 1024);
    try io_event_loop.read(terminal.shell.stdout.?, buf, ptyReadCallback, terminal);

    return .{
        .allocator = allocator,
        .window = window,
        .renderer = renderer,
        .io_event_loop = io_event_loop,

        .buf = buf,
        .terminal = terminal,
    };
}

pub fn run(self: *App) !void {
    self.terminal.vtparser.user_data = self.terminal;

    var running = true;

    var timer = try std.time.Timer.start();
    var frames: usize = 0;

    var cache = font.Cache.init(self.allocator);
    defer cache.deinit();

    const font_ttf = try font.Font.init(assets.fonts.@"FiraCodeNerdFontMono-Regular.ttf", 32, 32);
    defer font_ttf.deinit();

    const ttf = font_ttf.ttf;

    while (running) {
        self.window.poll();
        try self.io_event_loop.poll(0);

        while (self.window.nextEvent()) |event| {
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
                },
                .input => |input_event| {
                    switch (input_event) {
                        .utf8_codepoint => |codepoint| {
                            var buff: [4]u8 = undefined;
                            const len = try std.unicode.utf8Encode(codepoint, &buff);
                            try self.terminal.shell.stdin.?.writeAll(buff[0..len]);
                        },
                        .keyboard => |key_event| {
                            if (key_event.type == .press and key_event.code == 28)
                                try self.terminal.shell.stdin.?.writeAll("\r\n");
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        var instance_list: std.ArrayList(TextInstance) = .empty;
        defer instance_list.deinit(self.allocator);

        var pixels_pool: std.ArrayList(u8) = .empty;
        defer pixels_pool.deinit(self.allocator);

        var row: u32 = 0;
        var col: u32 = 0;

        for (self.terminal.grid.rows_list.items) |line| {
            const cells = self.terminal.grid
                .backing_store[line.cells_offset .. line.cells_offset + line.cells_len];

            for (cells) |cell| {
                if (cell.unicode == ' ') {
                    col += 1;
                    continue;
                }
                const glyph_id = font.GlyphID{
                    .font = @enumFromInt(0),
                    .index = @enumFromInt(cell.unicode),
                };
                const glyph_entry =
                    cache.getAtlasEntry(glyph_id) orelse blk: {
                        const index = ttf.codepointGlyphIndex(@intCast(cell.unicode));
                        const bmp = try ttf.glyphBitmap(
                            self.allocator,
                            &pixels_pool,
                            index,
                            font_ttf.scale_x,
                            font_ttf.scale_y,
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
                    .p_postion = (row & 0xFFFF) | (col << 16),
                    .p_glyph_entry = @bitCast(glyph_entry),
                    .fg_color = cell.fg_color,
                    .bg_color = cell.bg_color,
                });

                col += 1;
            }
            row += 1;
            col = 0;
        }

        try self.renderer.beginFrame();

        try self.renderer.setViewport(
            0,
            0,
            self.window.width(),
            self.window.height(),
        );

        self.renderer.clear(.black);

        if (cache.new_added_entries.items.len > 0) {
            try self.renderer.cacheGlyphs(
                cache.new_added_entries.items,
                pixels_pool.items,
            );

            cache.new_added_entries.clearRetainingCapacity();
        }

        if (instance_list.items.len != 0) {
            const batch = try self.renderer.reserveBatch(instance_list.items.len);
            @memcpy(batch, instance_list.items);

            try self.renderer.commitBatch(instance_list.items.len);
        }

        try self.renderer.endFrame();
        try self.renderer.presnt();

        frames += 1;

        const diff = timer.read();

        if (diff >= std.time.ns_per_s) {
            const secands = @as(f64, @floatFromInt(diff)) * (1.0 / @as(comptime_float, std.time.ns_per_s));
            const fps = @as(f64, @floatFromInt(frames)) / secands;

            var buf: [255]u8 = undefined;
            const title = try std.fmt.bufPrintZ(&buf, "zerotty - FPS: {:.02}", .{fps});
            try self.window.setTitle(title);

            frames = 0;
            timer.reset();
        }
    }
}

pub fn deinit(self: *App) void {
    self.renderer.deinit();
    self.window.destroy(self.allocator);
    self.io_event_loop.deinit(self.allocator);
    self.terminal.deinit(self.allocator);
    self.allocator.free(self.buf);

    self.allocator.destroy(self.terminal);

    AssetsManager.instance.deinit(self.allocator);
}

fn ptyReadCallback(event: *io.EventLoop.Event, len: usize, user_data: ?*anyopaque) io.EventLoop.CallbackAction {
    const buffer = event.request.op_data.read[0..len];
    const terminal: *Terminal = @ptrCast(@alignCast(user_data));
    terminal.vtparser.parse(buffer);
    return .retry;
}

const std = @import("std");
const builtin = @import("builtin");
const io = @import("io");
const win = @import("window");
const font = @import("font");
const assets = @import("assets");
const Terminal = @import("Terminal.zig");
const AssetsManager = @import("AssetsManager");
const TextInstance = @import("renderer").vertex.TextInstance;
const Renderer = @import("renderer").Renderer;

const os_tag = builtin.os.tag;
