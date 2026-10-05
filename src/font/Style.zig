//! Font style *requests*.
//!
//! This file names what the user can ask for. It performs no rasterization and
//! no font loading — those belong to `FontInterface` and `FontManager`. Keeping
//! the request types free of behavior means the "which file do I need" question
//! has exactly one answer site (`keyOf`) rather than one per lookup path.

const std = @import("std");

/// The two toggles a terminal exposes directly. These select a face; they do
/// not describe how to draw one.
pub const Style = packed struct {
    bold: bool = false,
    italic: bool = false,
};

/// A font weight, as an enum rather than independent booleans.
///
/// The earlier `FontFlags` used eight `bool`s (`bold`, `extra_bold`, `light`,
/// ...), which made "two weights set at once" representable. That is how
/// `assets.zon` came to contain entries whose flags were internally
/// inconsistent. An enum makes the invalid state unrepresentable instead of
/// merely discouraged.
pub const Weight = enum(u8) {
    thin,
    extra_light,
    light,
    regular,
    medium,
    semi_bold,
    bold,
    extra_bold,

    /// Ordering used when snapping a request to the nearest available face.
    pub fn rank(w: Weight) u8 {
        return @intFromEnum(w);
    }
};

/// A typeface family. These two differ only in whether coding ligatures are
/// baked into the outlines; zerotty does not currently render ligatures, so
/// they produce identical glyphs today.
pub const Family = enum(u8) {
    jetbrains_mono,
    jetbrains_mono_nl,

    /// Strips a "-NL" suffix from an asset filename.
    pub fn fromFileName(name: []const u8) ?Family {
        if (std.mem.endsWith(u8, name, "-NL.ttf")) return .jetbrains_mono_nl;
        if (std.mem.endsWith(u8, name, "-NLItalic.ttf")) return .jetbrains_mono;
        if (std.mem.endsWith(u8, name, ".ttf")) return .jetbrains_mono;
        return null;
    }
};

/// Identity of a single installable face: which family, which weight, upright
/// or slanted. This is the key of the comptime font table, and it must be
/// unique across all entries.
pub const Key = packed struct {
    family: Family,
    weight: Weight,
    italic: bool,
};

/// The weight a request resolves to when the exact one is unavailable.
///
/// Synthetic bold/italic (embolden, oblique) is deliberately not implemented
/// yet. Snapping to the nearest real face is the whole policy for now, and it
/// lives here so that adding synthesis later means changing one function
/// rather than teaching every lookup path about it.
pub fn defaultWeight(style: Style) Weight {
    return if (style.bold) .bold else .regular;
}

/// Builds the registry lookup key for a style/weight request.
pub fn keyOf(style: Style, weight: Weight, family: Family) Key {
    return .{
        .family = family,
        .weight = weight,
        .italic = style.italic,
    };
}

comptime {
    std.testing.refAllDecls(@This());
}

test "default weight follows bold" {
    try std.testing.expectEqual(Weight.regular, defaultWeight(.{}));
    try std.testing.expectEqual(Weight.bold, defaultWeight(.{ .bold = true }));
}

test "keyOf preserves every component" {
    const k = keyOf(.{ .bold = true, .italic = true }, .semi_bold, .jetbrains_mono_nl);
    try std.testing.expectEqual(Family.jetbrains_mono_nl, k.family);
    try std.testing.expectEqual(Weight.semi_bold, k.weight);
    try std.testing.expect(k.italic);
}

test "weights are ordered thin..extra_bold" {
    try std.testing.expect(Weight.rank(.thin) < Weight.rank(.light));
    try std.testing.expect(Weight.rank(.light) < Weight.rank(.regular));
    try std.testing.expect(Weight.rank(.regular) < Weight.rank(.medium));
    try std.testing.expect(Weight.rank(.medium) < Weight.rank(.semi_bold));
    try std.testing.expect(Weight.rank(.semi_bold) < Weight.rank(.bold));
    try std.testing.expect(Weight.rank(.bold) < Weight.rank(.extra_bold));
}
