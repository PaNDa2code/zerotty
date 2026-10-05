const FontManager = @This();

const std = @import("std");
const zerotty = @import("zerotty");
const PerfectHashMap = zerotty.ds.zmph.PerfectHashMap;
const Style = @import("Style.zig");

/// Which faces are installed, as a compile-time constant table.
///
/// The key is `Style.Key` (family + weight + italic) rather than a bag of
/// weight booleans. Bare weight flags could not distinguish `JetBrainsMono-Bold`
/// from `JetBrainsMonoNL-Bold`, so both landed in the table under one key --
/// and a perfect hash map cannot hold two identical keys, because both would
/// hash to the same slot under every displacement. `Style.Weight` also makes
/// "two weights set at once" unrepresentable.
pub const fonts = PerfectHashMap(Style.Key, []const u8).comptimeInit(list: {
    const assets_zon = @import("font_registry.zon");
    var list: [assets_zon.len]struct { Style.Key, []const u8 } = undefined;

    for (0.., assets_zon) |i, ast| {
        list[i] = .{ Style.Key{
            .family = ast.family,
            .weight = ast.weight,
            .italic = ast.italic,
        }, ast.name };
    }

    break :list list;
});

comptime {
    // The face App.zig loads directly must be reachable through the table too,
    // otherwise the registry and the hardcoded startup path can drift apart.
    _ = fonts.get(.{
        .family = .jetbrains_mono,
        .weight = .regular,
        .italic = false,
    }) orelse unreachable;

    // Full coverage: every family/weight/italic combination must be installed,
    // so adding a Weight variant fails the build until the table is updated.
    for (std.enums.values(Style.Family)) |family| {
        for (std.enums.values(Style.Weight)) |weight| {
            for ([_]bool{ false, true }) |italic| {
                const key = Style.Key{ .family = family, .weight = weight, .italic = italic };
                if (!fonts.has(key))
                    @compileError("assets.zon is missing a face for " ++ @tagName(family) ++
                        "/" ++ @tagName(weight) ++ (if (italic) "/italic" else "/upright"));
            }
        }
    }
}

test "every family/weight/italic combination resolves" {
    for (std.enums.values(Style.Family)) |family| {
        for (std.enums.values(Style.Weight)) |weight| {
            for ([_]bool{ false, true }) |italic| {
                const key = Style.Key{ .family = family, .weight = weight, .italic = italic };
                try std.testing.expect(fonts.has(key));
            }
        }
    }
}
