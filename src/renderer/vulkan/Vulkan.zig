const VulkanRenderer = @This();

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

pub fn init(window: *Window, allocator: Allocator) !VulkanRenderer {
    var self: VulkanRenderer = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *VulkanRenderer, window: *Window, allocator: Allocator) !void {
    const core = try Core.init(allocator, window);

    const swap_chain = try SwapChain.init(&core, window.height, window.width);
    const descriptor = try Descriptor.init(&core);
    const pipe_line = try Pipeline.init(&core, &swap_chain, &descriptor);
    const cmd = try Command.init(&core, 2);
    const sync = try Sync.init(&core, &swap_chain);

    self.atlas = try Atlas.create(allocator, 30, 20, 0, 128);

    const tex = try Texture.init(&core, .{
        .height = @intCast(self.atlas.height),
        .width = @intCast(self.atlas.width),
    });

    const grid_rows = window.height / self.atlas.cell_height;
    const grid_cols = window.width / self.atlas.cell_width;

    self.grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });

    const vertex_memory_size = 1024 * 16;
    const altas_size = self.atlas.buffer.len;

    const staging_memory_size = @max(altas_size, vertex_memory_size);

    const buffers = try Buffers.init(&core, .{
        .staging_size = staging_memory_size,
        .vertex_size = staging_memory_size,
        .uniform_size = 16 * 1024,
    });

    self.window_height = window.height;
    self.window_width = window.width;

    try buffers.updateUniformData(&core, &.{
        .cell_height = @floatFromInt(self.atlas.cell_height),
        .cell_width = @floatFromInt(self.atlas.cell_width),
        .screen_height = @floatFromInt(self.window_height),
        .screen_width = @floatFromInt(self.window_width),
        .atlas_cols = @floatFromInt(self.atlas.cols),
        .atlas_rows = @floatFromInt(self.atlas.rows),
        .atlas_height = @floatFromInt(self.atlas.height),
        .atlas_width = @floatFromInt(self.atlas.width),
        .descender = @floatFromInt(self.atlas.descender),
    });

    try tex.uploadAtlas(
        &core,
        &buffers,
        &cmd,
        &self.atlas,
    );

    try buffers.stageVertexData(
        &core,
        &self.grid,
        &self.atlas,
    );

    try descriptor.updateDescriptorSets(
        &core,
        &buffers,
        tex.image_view,
        tex.sampler,
    );

    self.core = core;
    self.cmd = cmd;
    self.buffers = buffers;
    self.pipe_line = pipe_line;
    self.swap_chain = swap_chain;
    self.sync = sync;
    self.descriptor = descriptor;
    self.tex = tex;
}

pub fn deinit(self: *VulkanRenderer) void {
    self.core.dispatch.vkd
        .deviceWaitIdle(self.core.device) catch unreachable;

    self.grid.free();
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

pub fn clearBuffer(self: *VulkanRenderer, color: ColorRGBAf32) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *VulkanRenderer, width: u32, height: u32) !void {
    _ = self;
    _ = width;
    _ = height;
}

pub fn presentBuffer(self: *VulkanRenderer) void {
    drawFrame(self) catch @panic("drawFrame failed");
}

pub fn renaderGrid(self: *VulkanRenderer) void {
    _ = self;
}

pub fn setCell(
    self: *VulkanRenderer,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    const glyph_info = self.atlas.glyph_lookup_map.get(char_code) orelse self.atlas.glyph_lookup_map.get(' ').?;

    try self.grid.set(.{
        .row = row,
        .col = col,
        .char = char_code,
        .fg_color = fg_color orelse .White,
        .bg_color = bg_color orelse .Black,
        .glyph_info = glyph_info,
    });
}

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");
const common = @import("../common.zig");

const Core = @import("Core.zig");
const SwapChain = @import("SwapChain.zig");
const Descriptor = @import("Descriptor.zig");
const Pipeline = @import("Pipeline.zig");
const Buffers = @import("Buffers.zig");
const Sync = @import("Sync.zig");
const Command = @import("Command.zig");
const Texture = @import("Texture.zig");

const Window = @import("../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = common.ColorRGBAu8;
const ColorRGBAf32 = common.ColorRGBAf32;
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const VkAllocatorAdapter = @import("VkAllocatorAdapter.zig");
const Grid = @import("../Grid.zig");
const Atlas = @import("../../font/Atlas.zig");

const helpers = @import("helpers/root.zig");
const setupDebugMessenger = helpers.debug.setupDebugMessenger;

const drawFrame = @import("frames.zig").drawFrame;
