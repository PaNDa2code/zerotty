const std = @import("std");

pub fn findESCs(allocator: std.mem.Allocator, buffer: []const u8) !std.SinglyLinkedList(usize) {
    const Node = std.SinglyLinkedList(usize).Node;

    const v_len = std.simd.suggestVectorLength(u8) orelse @compileError("Can't get the suggested vector length");
    const ByteVec = @Vector(v_len, u8);

    const esc_vec: ByteVec = comptime @splat(0x1b);
    const null_vec: ByteVec = comptime @splat(0xff);
    const indcies = comptime std.simd.iota(u8, v_len);

    var chunk: ByteVec = undefined;

    var i: usize = 0;

    var dummy = Node{ .data = 0 };
    var node = &dummy;

    while (i + v_len <= buffer.len) : (i += v_len) {
        chunk = buffer[i..][0..v_len].*;
        const matches = chunk == esc_vec;
        if (!@reduce(.Or, matches)) {
            continue;
        }
        const index_vec: ByteVec = @select(u8, matches, indcies, null_vec);
        for (0..v_len) |idx| {
            if (index_vec[idx] != 0xff) {
                var new = try allocator.create(Node);
                new.data = i + idx;
                node.insertAfter(new);
                node = new;
            }
        }
    }

    if (i < buffer.len) {
        chunk = null_vec;

        var tail = [_]u8{0} ** v_len;
        @memcpy(tail[0 .. buffer.len - i], buffer[i..]);
        chunk = @bitCast(tail);

        const matches = chunk == esc_vec;
        if (@reduce(.Or, matches)) {
            const index_vec = @select(u8, matches, indcies, null_vec);
            for (0..v_len) |idx| {
                if (index_vec[idx] != 0xff and idx < buffer.len - i) {
                    var new = try allocator.create(Node);
                    new.data = i + idx;
                    node.insertAfter(new);
                    node = new;
                }
            }
        }
    }

    return std.SinglyLinkedList(usize){ .first = dummy.next };
}

// fn parseEscSeq(buffer: []const u8, index: usize) void {
//     if (buffer.len == 0) return;
//
//     if (buffer[0] != '\x1b') return;
//
//     for(buffer[1..]) |c| {
//
//     }
// }

test {
    const allocator = std.testing.allocator;
    var buffer: [147]u8 = undefined;
    buffer[5] = 0x1b;
    buffer[127] = 0x1b;
    buffer[146] = 0x1b;

    var indcies = try findESCs(allocator, &buffer);

    try std.testing.expect(indcies.len() == 3);
    while (indcies.popFirst()) |node| : (allocator.destroy(node)) {
        try std.testing.expectEqual(buffer[node.data], 0x1b);
    }
}
