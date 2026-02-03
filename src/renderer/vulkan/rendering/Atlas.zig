const Atlas = @This();


textures: std.ArrayList(Texture),
glyphs_entries: std.AutoArrayHashMap(font.GlyphID, font.GlyphAtlasEntry),

const std = @import("std");
const core = @import("core");
const font = @import("font");
const Texture = @import("Texture.zig");
