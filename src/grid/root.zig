const std = @import("std");
const color = @import("color");

pub const Grid = struct {
    allocator: std.mem.Allocator,

    backing_store: []Cell,
    cells_head: usize = 0,
    cells_count: usize = 0,

    rows_list: std.ArrayList(Row) = .empty,

    display_offset: usize = 0,
    visable_rows: usize = 0,

    columns: usize = 0,

    pub const GridOptions = struct {
        visable_columns: usize,
        visable_rows: usize,
        max_cells: usize = 2 * 1024 * 1024,
    };

    pub fn init(allocator: std.mem.Allocator, options: GridOptions) !Grid {
        const backing_store = try allocator.alloc(Cell, options.max_cells);

        var rows_list = try std.ArrayList(Row).initCapacity(
            allocator,
            options.visable_rows,
        );

        rows_list.appendAssumeCapacity(.{
            .cells_len = 0,
            .cells_offset = 0,
            .flags = .{},
        });

        return .{
            .allocator = allocator,
            .backing_store = backing_store,
            .rows_list = rows_list,
        };
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.backing_store);
        self.rows_list.deinit(self.allocator);
    }

    pub fn resize(self: *Grid, new_cols: usize) !void {
        if (self.columns > new_cols) {
            return self.shrink_cols(new_cols);
        }

        if (self.columns < new_cols) {
            return self.grow_cols(new_cols);
        }
    }

    pub fn appendCell(self: *Grid, cell: Cell) !void {
        self.backing_store[self.cells_head..][self.cells_count] = cell;
        self.rows_list.items[self.rows_list.items.len].cells_len += 1;
    }

    pub fn appendRow(self: *Grid) !void {
        self.visable_rows += 1;

        self.rows_list.appendAssumeCapacity(.{
            .cells_offset = self.cells_count,
            .cells_len = 0,
            .flags = .{
                .wrapped = true,
            },
        });
    }

    // fn grow_cols(self: *Grid, new_cols: usize) !void {}
    // fn shrink_cols(self: *Grid, new_cols: usize) !void {}
};

pub const Row = struct {
    pub const Flags = packed struct {
        wrapped: bool = false,
    };

    cells_offset: usize,
    cells_len: usize,

    flags: Flags,

    // pub fn shrink_cells(self: *Row, shrink_to: usize) []Cell {}
    // pub fn grow_cells(self: *Row, grow_to: usize, forword: bool) void {}
};

pub const Cell = struct {
    code: u32,
    fg_color: color.RGBA,
    bg_color: color.RGBA,
    flags: color.ansi.Flags,
};
