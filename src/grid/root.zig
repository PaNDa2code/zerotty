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

    pub const Iter = struct {
        grid: *const Grid,

        screen_cols: usize,
        screen_rows: usize,

        scroll_offset: usize,

        current_x: usize = 0,
        current_y: usize = 0,

        pub const Item = struct {
            x: usize,
            y: usize,
            cell: Cell,
        };

        pub fn next(self: *Iter) ?Item {
            if (self.current_y >= self.screen_rows) return null;

            const x = self.current_x;
            const y = self.current_y;

            var cell: Cell = .{
                .unicode = 0,
                .bg_color = .black,
                .fg_color = .white,
                .flags = .{},
            };

            const total_rows = self.grid.rows_list.items.len;

            if (total_rows > 0) {
                if (self.getLogicalRowIndex(y, total_rows)) |logical_y| {
                    const row = self.grid.rows_list.items[logical_y];

                    if (x < row.cells_len) {
                        const physical_idx = row.cells_offset + x;
                        cell = self.grid.backing_store[physical_idx];
                    }
                }
            }

            self.current_x += 1;
            if (self.current_x >= self.screen_cols) {
                self.current_x = 0;
                self.current_y += 1;
            }

            return .{ .x = x, .y = y, .cell = cell };
        }
        fn getLogicalRowIndex(self: *const Iter, screen_y: usize, total_rows: usize) ?usize {
            if (total_rows < self.screen_rows) {
                // TERMINAL STARTUP BEHAVIOR:
                // Text is top-aligned. Screen Y maps directly to Logical Y.
                if (screen_y < total_rows) {
                    return screen_y;
                }
                return null; // Blank lines at the bottom of the screen
            } else {
                // TERMINAL SCROLLING BEHAVIOR:
                // Text is bottom-aligned and pushed up.
                const absolute_bottom = total_rows - 1 - self.scroll_offset;
                const visual_distance_from_bottom = (self.screen_rows - 1) - screen_y;

                if (absolute_bottom >= visual_distance_from_bottom) {
                    return absolute_bottom - visual_distance_from_bottom;
                }
                return null; // Blank lines at the top of the screen (if scrolled way past history)
            }
        }
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
        self.cells_count += 1;
        self.rows_list.items[self.rows_list.items.len - 1].cells_len += 1;
    }

    pub fn appendRow(self: *Grid) !void {
        self.visable_rows += 1;

        self.rows_list.appendAssumeCapacity(.{
            .cells_offset = self.cells_count,
            .cells_len = 0,
            .flags = .{},
        });
    }

    pub fn iter(
        self: *const Grid,
        screen_cols: usize,
        screen_rows: usize,
        scroll_offset: usize,
    ) Iter {
        return .{
            .grid = self,
            .screen_cols = screen_cols,
            .screen_rows = screen_rows,
            .scroll_offset = scroll_offset,
        };
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
    unicode: u32,
    fg_color: color.RGBA,
    bg_color: color.RGBA,
    flags: color.ansi.Flags,
};
