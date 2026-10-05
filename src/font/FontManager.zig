const FontManager = @This();

const PerfectHashMap = @import("zerotty").ds.zmph.PerfectHashMap;

pub const FontFlags = packed struct(u8) {
    bold: bool = false,
    italic: bool = false,
    extra_bold: bool = false,
    extra_light: bool = false,
    light: bool = false,
    medium: bool = false,
    semi_bold: bool = false,
    thin: bool = false,
};

pub const ttf_names_map = PerfectHashMap(FontFlags, []const u8).comptimeInit(list: {
    const assets_zon = @import("assets.zon");
    var list: [assets_zon.len]struct { FontFlags, []const u8 } = undefined;

    for (0.., assets_zon) |i, ast| {
        list[i] = .{ FontFlags{
            .bold = ast.flags.bold,
            .italic = ast.flags.italic,
            .extra_bold = ast.flags.extra_bold,
            .extra_light = ast.flags.extra_light,
            .light = ast.flags.light,
            .medium = ast.flags.medium,
            .semi_bold = ast.flags.semi_bold,
            .thin = ast.flags.thin,
        }, ast.name };
    }

    break :list list;
});
