const std = @import("std");
const builtin = @import("builtin");

const native_endian = builtin.cpu.arch.endian();

const TableId = enum(u32) {
    // required tables
    cmap = fromStr("cmap"),
    glyf = fromStr("glyf"),
    head = fromStr("head"),
    hhea = fromStr("hhea"),
    hmtx = fromStr("hmtx"),
    loca = fromStr("loca"),
    maxp = fromStr("maxp"),
    name = fromStr("name"),
    post = fromStr("post"),

    // optional tables
    @"cvt " = fromStr("cvt "),
    fpgm = fromStr("fpgm"),
    hdmx = fromStr("hdmx"),
    kern = fromStr("kern"),
    @"OS/2" = fromStr("OS/2"),
    prep = fromStr("prep"),

    _,

    pub fn toInt(id: TableId) u32 {
        const tag_name: [4]u8 = @tagName(id)[0..4];
        return @bitCast(tag_name);
    }

    pub fn fromStr(s: [4]u8) TableId {
        return @bitCast(s);
    }
};


const SubTable = extern struct {
    scaler_type: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};
