pub const fonts = struct {
    pub const @"FiraCodeNerdFontMono-Regular.ttf" = compress(@embedFile("fonts/FiraCodeNerdFontMono-Regular.ttf"));
    pub const @"FiraCodeNerdFontMono-Bold.ttf" = compress(@embedFile("fonts/FiraCodeNerdFontMono-Bold.ttf"));
};

pub const icons = struct {
    pub const @"logo.ico" = compress(@embedFile("logo.ico"));
};

pub const shaders = struct {
    pub const cell_vert = @embedFile("cell.vert.spv");
    pub const cell_frag = @embedFile("cell.frag.spv");
};

const std = @import("std");

pub const compress = @import("compress.zig").compress;
pub const decompress = @import("compress.zig").decompress;
