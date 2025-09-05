const std = @import("std");
const vtparse = @import("vtparse");

fn callpack(state: *const vtparse.ParserData, to_action: vtparse.Action, char: u8) void {
    std.log.debug("{s}=>{s}: {x:02}\n", .{ @tagName(state.state), @tagName(to_action), char });
}

pub fn parseEsape(slice: []const u8) void {
    var parser = vtparse.VTParser.init(callpack, null);
    parser.parse(slice);
}

test {
    parseEsape("\x1b\x5b\x48\x1b\x5b\x32\x4a\x1b\x5b\x33\x4a");
}
