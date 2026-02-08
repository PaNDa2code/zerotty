const Cache = @This();

textures: std.ArrayList(Texture),

max_textures_len: u32,
textures_width: u32,
textures_height: u32,

pub fn init(
    textures_width: u32,
    textures_height: u32,
    max_textures_len: u32,
) Cache {
    std.debug.assert(textures_width <= font.max_atlas_dim and
        textures_height <= font.max_atlas_dim and
        max_textures_len <= font.max_atlases_count);

    return .{
        .textures = .empty,
        .textures_width = @min(font.max_atlas_dim, textures_width),
        .textures_height = @min(font.max_atlas_dim, textures_height),
        .max_textures_len = @min(font.max_atlases_count, max_textures_len),
    };
}

pub fn newTexture(
    self: *Cache,
    allocator: std.mem.Allocator,
    device_allocator: *memory.DeviceAllocator,
) !*Texture {
    const texture = try Texture.init(device_allocator, .{
        .width = self.textures_width,
        .height = self.textures_height,
    });
    try self.textures.append(allocator, texture);
    return &self.textures.items[self.textures.items.len - 1];
}

pub fn deinit(
    self: *Cache,
    allocator: std.mem.Allocator,
    device_allocator: *memory.DeviceAllocator,
) void {
    for (self.textures.items) |*texture| {
        texture.deinit(device_allocator);
    }
    self.textures.deinit(allocator);
}

const std = @import("std");
const core = @import("core");
const memory = core.memory;
const font = @import("font");
const Texture = @import("Texture.zig");
