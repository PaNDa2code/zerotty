const Backend = @This();

context: *const Context,
target: Target,

window_height: u32,
window_width: u32,

atlas: Atlas,
grid: Grid,

allocator_adapter: *AllocatorAdapter,

pub const log = std.log.scoped(.Renderer);

pub fn init(window: *Window, allocator: Allocator) !Backend {
    var self: Backend = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *Backend, window: *Window, allocator: Allocator) !void {
    self.allocator_adapter = try allocator.create(AllocatorAdapter);

    self.allocator_adapter.initInPlace(allocator);

    const instance_extensions = Target.instanceExtensions(.windowed);
    const device_extensions = Target.deviceExtensions(.windowed);

    // Instance and Device are temporary.
    // They are created only to initialize Context.
    // Context takes ownership and cleans them up.
    const instance = try Context.Instance.init(
        allocator,
        &self.allocator_adapter.alloc_callbacks,
        instance_extensions,
    );
    // errdefer instance.deinit();

    const wsi_surface = try Target.WsiSurface.create(instance, window);
    // errdefer wsi_surface.destroy();

    const device = try Context.Device.init(
        allocator,
        &instance,
        wsi_surface.handle,
        device_extensions,
    );
    // errdefer device.deinit();

    self.context = try Context.init(allocator, instance, device);

    self.target = try Target.initWsi(allocator, self.context, wsi_surface);

    self.atlas = try Atlas.loadAll(allocator, 22, 15, 2000);

    const grid_rows = window.height / self.atlas.cell_height;
    const grid_cols = window.width / self.atlas.cell_width;

    self.grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });
}

pub fn deinit(self: *Backend) void {
    const allocator = self.allocator_adapter.allocator;
    self.grid.free(allocator);
    self.atlas.deinit(allocator);

    self.target.deinit(allocator);

    self.context.deinit(allocator);
    self.allocator_adapter.deinit();

    allocator.destroy(self.allocator_adapter);
}

pub fn clearBuffer(self: *Backend, color: ColorRGBAf32) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *Backend, width: u32, height: u32) !void {
    const grid_rows = height / self.atlas.cell_height;
    const grid_cols = width / self.atlas.cell_width;

    try self.grid.resize(self.allocator_adapter.allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });
}

pub fn presentBuffer(self: *Backend) void {
    _ = self; // autofix
}

pub fn renaderGrid(self: *Backend) void {
    _ = self;
}

pub fn setCell(
    self: *Backend,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    _ = bg_color;
    _ = fg_color;

    const glyph_index = self.atlas.glyph_lookup_map.getIndex(char_code) orelse 0;

    try self.grid.set(.{
        .packed_pos = (col << 16) | row,
        .glyph_index = @intCast(glyph_index),
        .style_index = 0,
    });
}

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");

const Context = @import("core/Context.zig");
const Target = @import("target/Interface.zig");

const Window = @import("../../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = @import("../../common/color.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("../../common/color.zig").ColorRGBAf32;
const DynamicLibrary = @import("../../../DynamicLibrary.zig");
const AllocatorAdapter = @import("memory/AllocatorAdapter.zig");
const Grid = @import("../../../Grid.zig");
const Atlas = @import("../../../font/Atlas.zig");

const helpers = @import("helpers/root.zig");
const setupDebugMessenger = helpers.debug.setupDebugMessenger;

const drawFrame = @import("frames.zig").drawFrame;
