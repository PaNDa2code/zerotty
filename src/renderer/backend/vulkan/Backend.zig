const Backend = @This();

core: Core,
swap_chain: SwapChain,
pipe_line: Pipeline,
buffers: Buffers,
sync: Sync,
cmd: Command,
tex: Texture,
descriptor: Descriptor,

window_height: u32,
window_width: u32,

atlas: Atlas,
grid: Grid,

pub const log = std.log.scoped(.Renderer);

pub fn init(window: *Window, allocator: Allocator) !Backend {
    var self: Backend = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *Backend, window: *Window, allocator: Allocator) !void {
    const core = try Core.init(allocator, window);

    const swap_chain = try SwapChain.init(&core, window.height, window.width);
    const descriptor = try Descriptor.init(&core);
    const pipe_line = try Pipeline.init(&core, &swap_chain, &descriptor);
    const cmd = try Command.init(&core, 2);
    const sync = try Sync.init(&core, &swap_chain);

    const atlas = try Atlas.loadAll(allocator, 22, 15, 2000);

    const tex = try Texture.init(&core, .{
        .height = @intCast(atlas.height),
        .width = @intCast(atlas.width),
    });

    const grid_rows = window.height / atlas.cell_height;
    const grid_cols = window.width / atlas.cell_width;

    const grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });

    const vertex_memory_size = 1024 * 1024 * 512;
    const altas_size = atlas.buffer.len;

    const staging_memory_size = @max(altas_size, vertex_memory_size);

    var buffers = try Buffers.init(&core, .{
        .staging_size = staging_memory_size,
        .vertex_size = staging_memory_size,
        .uniform_size = 16 * 1024,
        .glyph_ssbo_size = atlas.glyph_lookup_map.values().len * @sizeOf(Atlas.GlyphInfo),
        .style_ssbo_size = 1024 * 16,
    });

    try buffers.updateUniformData(&core, &.{
        .cell_height = @floatFromInt(atlas.cell_height),
        .cell_width = @floatFromInt(atlas.cell_width),
        .screen_height = @floatFromInt(window.height),
        .screen_width = @floatFromInt(window.width),
        .atlas_cols = @floatFromInt(atlas.cols),
        .atlas_rows = @floatFromInt(atlas.rows),
        .atlas_height = @floatFromInt(atlas.height),
        .atlas_width = @floatFromInt(atlas.width),
        .descender = @floatFromInt(atlas.descender),
    });

    try tex.uploadAtlas(
        &core,
        &buffers,
        &cmd,
        &atlas,
    );

    try descriptor.updateDescriptorSets(
        &core,
        &buffers,
        tex.image_view,
        tex.sampler,
    );

    self.* = .{
        .core = core,
        .cmd = cmd,
        .buffers = buffers,
        .pipe_line = pipe_line,
        .swap_chain = swap_chain,
        .sync = sync,
        .descriptor = descriptor,
        .tex = tex,

        .window_height = window.height,
        .window_width = window.width,

        .atlas = atlas,
        .grid = grid,
    };
}

pub fn deinit(self: *Backend) void {
    self.core.dispatch.vkd
        .deviceWaitIdle(self.core.device) catch unreachable;

    self.grid.free(self.core.vk_mem.allocator);
    self.atlas.deinit(self.core.vk_mem.allocator);

    self.cmd.deinit(&self.core);

    self.buffers.deinit(&self.core);

    self.tex.deinit(&self.core);

    self.sync.deinit(&self.core);

    self.pipe_line.deinit(&self.core);

    self.descriptor.deinit(&self.core);

    self.swap_chain.deinit(&self.core);

    self.core.deinit();
}

pub fn clearBuffer(self: *Backend, color: ColorRGBAf32) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *Backend, width: u32, height: u32) !void {
    try self.core.waitDeviceIdle();

    try self.swap_chain.recreate(&self.core, height, width);
    try self.pipe_line.recreateFrameBuffers(&self.core, &self.swap_chain);

    Buffers.uniform_buffer_ptr.?.screen_height = @floatFromInt(height);
    Buffers.uniform_buffer_ptr.?.screen_width = @floatFromInt(width);

    const grid_rows = height / self.atlas.cell_height;
    const grid_cols = width / self.atlas.cell_width;

    try self.grid.resize(self.core.vk_mem.allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });
}

pub fn presentBuffer(self: *Backend) void {
    self.buffers.updateSSBOs(
        &self.core,
        &self.atlas,
    ) catch unreachable;

    self.buffers.stageVertexData(
        &self.core,
        &self.grid,
    ) catch unreachable;

    drawFrame(self) catch @panic("drawFrame failed");
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

const Core = @import("Core.zig");
const SwapChain = @import("SwapChain.zig");
const Descriptor = @import("Descriptor.zig");
const Pipeline = @import("Pipeline.zig");
const Buffers = @import("Buffers.zig");
const Sync = @import("Sync.zig");
const Command = @import("Command.zig");
const Texture = @import("Texture.zig");

const Window = @import("../../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = @import("../../common/color.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("../../common/color.zig").ColorRGBAf32;
const DynamicLibrary = @import("../../../DynamicLibrary.zig");
const VkAllocatorAdapter = @import("VkAllocatorAdapter.zig");
const Grid = @import("../../../Grid.zig");
const Atlas = @import("../../../font/Atlas.zig");

const helpers = @import("helpers/root.zig");
const setupDebugMessenger = helpers.debug.setupDebugMessenger;

const drawFrame = @import("frames.zig").drawFrame;
