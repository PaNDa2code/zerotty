const std = @import("std");
const win = @import("window");
const root = @import("renderer");
const vertex = @import("vertex.zig");

const OpenGL = @import("OpenGL.zig");
const Vulkan = @import("Vulkan.zig");

pub fn GenaricRenderer(Impl: type) type {
    return struct {
        const Self = @This();

        inner: *Impl,

        pub const InitError = Impl.InitError;
        pub fn init(
            alloc: std.mem.Allocator,
            window_handles: win.WindowHandles,
            settings: root.RendererSettings,
        ) InitError!Self {
            const inner = try Impl.init(alloc, window_handles, settings);
            return .{
                .inner = inner,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        // pub fn resizeSurface(self: *Self, width: u32, height: u32) !void {}
        // pub fn setViewport(self: *Self, x: u32, y: u32, width: u32, height: u32) !void {}
        // pub fn cacheGlyphs(self: *Self, dimensions: []const GlyphBitmap, bitmap_pool: []const u8) !void {}
        // pub fn resetGlyphCache(self: *Self) !void {}
        // pub fn pushBatch(self: *Self) !void {}
        // pub fn reserveBatch(self: *Self, count: usize) ![]vertex.Instance {}
        // pub fn commitBatch(self: *Self, count: usize) !void {}
        // pub fn draw(self: *Self) !void {}
        // pub fn clear(self: *Self, bg_color: color.RGBA) void {}
        // pub fn beginFrame(self: *Self) void {}
        // pub fn endFrame(self: *Self) void {}
        // pub fn presnt(self: *Self) void {}
    };
}

comptime {
    _ = GenaricRenderer(OpenGL);
    _ = GenaricRenderer(Vulkan);
}
