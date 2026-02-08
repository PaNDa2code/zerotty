pub const Rectangle = struct { x: u16, y: u16, height: u16, width: u16 };

pub const Postion = struct { x: u16, y: u16 };

pub const Shelf = struct {
    current_width: u16,
    height: u16,
};

/// Single Atlas Packer (Shelf Algorithm)
///
/// Origin is Top-Left at (0, 0).
pub const Packer = struct {
    max_height: u32,
    max_width: u32,

    shelfs: std.ArrayList(Shelf),

    pub fn init(max_height: u32, max_width: u32) Packer {
        return .{
            .max_height = max_height,
            .max_width = max_width,
            .shelfs = .empty,
        };
    }

    pub fn deinit(self: *Packer, allocator: std.mem.Allocator) void {
        self.shelfs.deinit(allocator);
    }

    /// Finds the first available space in existing shelves
    /// or creates a new one (First-Fit strategy).
    /// Time complexity: O(N)
    pub fn findEmptyRectangle(
        self: *Packer,
        allocator: std.mem.Allocator,
        height: u16,
        width: u16,
    ) ?Postion {
        var height_tracker: u16 = 0;
        for (self.shelfs.items, 0..) |*shelf, i| {
            const is_last = i == self.shelfs.items.len - 1;

            if (!is_last and height > shelf.height or
                shelf.current_width + width > self.max_width or
                (is_last and height_tracker + height > self.max_height))
            {
                height_tracker += shelf.height;
                continue;
            }

            const x = shelf.current_width;
            const y = height_tracker;

            shelf.current_width += width;
            shelf.height = @max(height, shelf.height);

            return .{ .x = x, .y = y };
        }

        if (height_tracker + height > self.max_height)
            return null;

        const shelf = Shelf{
            .height = height,
            .current_width = width,
        };

        try self.shelfs.append(allocator, shelf);

        return .{
            .x = 0,
            .y = height_tracker,
        };
    }
};

const std = @import("std");

const root = @import("root.zig");
