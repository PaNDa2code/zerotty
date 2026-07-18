const Scrollback = @This();

const std = @import("std");

pub const Range = struct {
    from: usize,
    to: usize,
};

pub const FontStyle = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
};

pub const Style = struct {
    fg_color: @Vector(4, u8) = .{ 255, 255, 255, 255 },
    bg_color: @Vector(4, u8) = .{ 0, 0, 0, 255 },
    font_style: FontStyle,
};

// Logical line
pub const Line = struct {
    utf8: []u8 = &.{},
    ranges: []Range = &.{},
    styles: []Style = &.{},
};

pub const Block = struct {
    arina: std.heap.ArenaAllocator,
    lines: std.ArrayList(Line),

    pub fn init(alloc: std.mem.Allocator, lines: usize) !Block {
        return .{
            .arina = .init(alloc),
            .lines = .initCapacity(alloc, lines),
        };
    }

    pub fn deinit(self: *Block) void {
        self.lines.deinit(self.arina.child_allocator);
        self.arina.deinit();
    }
};

allocator: std.mem.Allocator,

max_lines: usize = 10_000,

blocks: std.ArrayList(Block) = .empty,
total_lines: usize = 0,

head: usize = 0,

pub fn init(allocator: std.mem.Allocator) void {
    return .{
        .allocator = allocator,
    };
}

pub fn pushData(self: *Scrollback, utf8: []const u8) !void {
    if (self.blocks.items.len == 0)
        try self.blocks.append(self.allocator, try Block.init(self.allocator, 500));

    var last_block = &self.blocks.items[self.blocks.items.len - 1];

    if (last_block.lines.items.len >= last_block.lines.capacity) {
        try self.blocks.append(self.allocator, .init(self.allocator, 500));
        last_block = &self.blocks.items[self.blocks.items.len - 1];
    }

    const arina = last_block.arina.allocator();
    const utf8_buff = try arina.dupe(u8, utf8);

    last_block.lines.append(self.allocator, .{
        .utf8 = utf8_buff,
    });

    self.total_lines += 1;

    if (self.total_lines > self.max_lines) {
        var first_block = &self.blocks.items[0];
        first_block.lines.items = first_block.lines.items[1..];
        self.total_lines -= 1;

        if (first_block.lines.items.len == 0) {
            first_block.deinit();
            self.blocks.orderedRemove(0);
        }
    }
}

pub fn newLine(self: *Scrollback) !void {
    _ = self;
}

pub fn setStyle(self: *Scrollback, style: Style) !void {
    _ = self;
    _ = style;
}

pub fn setFgColor(self: *Scrollback, color: @Vector(4, u8)) !void {
    _ = self;
    _ = color;
}

pub fn setBgColor(self: *Scrollback, color: @Vector(4, u8)) !void {
    _ = self;
    _ = color;
}

pub fn setFontStyle(self: *Scrollback, style: FontStyle) !void {
    _ = self;
    _ = style;
}
