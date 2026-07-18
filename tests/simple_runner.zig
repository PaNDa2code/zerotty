const std = @import("std");
const builtin = @import("builtin");

const TestStatus = enum { pass, fail, skip };

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, stdout_buffer[0..]);

    const writer = &stdout_writer.interface;

    const fail_first = false;

    var tests_ran: u32 = 0;
    var tests_failed: u32 = 0;
    var tests_skiped: u32 = 0;

    // Add a nice header
    try writer.writeAll("\n\x1b[1mRunning Tests...\x1b[0m\n\n");

    for (builtin.test_functions) |t| {
        std.testing.allocator_instance = .init;
        std.testing.environ = .{
            .block = .{ .slice = std.mem.span(std.c.environ) },
        };

        var status: TestStatus = .pass;
        var error_code: ?anyerror = null;

        t.func() catch |err| {
            status = .fail;
            error_code = err;
        };

        const color_code = switch (status) {
            .pass => "\x1b[32m", // Green
            .fail => "\x1b[31m", // Red
            .skip => "\x1b[33m", // Yellow
        };

        const icon = switch (status) {
            .pass => "✓",
            .fail => "✗",
            .skip => "⏸",
        };

        // 1. Truncate long names to prevent them from breaking the alignment
        const max_len = 50;
        var name_buf: [max_len + 3]u8 = undefined;
        const display_name = if (t.name.len > max_len)
            try std.fmt.bufPrint(&name_buf, "{s}...", .{t.name[0 .. max_len - 3]})
        else
            t.name;

        // 2. Print with dot-padding ({s:.<55}) so statuses align perfectly on the right
        try writer.print("  {s}{s}\x1b[0m {s: <55} {s}{s}\x1b[0m", .{
            color_code,
            icon,
            display_name,
            color_code,
            @tagName(status),
        });

        // 3. Make the error message pop with a grey arrow and red text
        if (error_code) |err| {
            try writer.print(" \x1b[90m=> \x1b[31m{s}\x1b[0m", .{@errorName(err)});
        }

        try writer.writeAll("\n");

        tests_ran += 1;

        switch (status) {
            .fail => tests_failed += 1,
            .skip => tests_skiped += 1,
            else => {},
        }

        if (fail_first and status == .fail) break;
    }

    const tests_passed = tests_ran - tests_failed - tests_skiped;

    const summary_color = if (tests_failed > 0) "\x1b[31m" else "\x1b[32m";
    const status_msg = if (tests_failed > 0) "FAILED" else "PASSED";

    // 4. Smooth Unicode summary box with individual number coloring
    try writer.print(
        \\
        \\{s}╭────────────────────────────────────────────────────────╮
        \\│                      Test Summary                      │
        \\╰────────────────────────────────────────────────────────╯{s}
        \\  Total:   {d}
        \\  Passed:  {s}{d}{s}
        \\  Failed:  {s}{d}{s}
        \\  Skipped: {s}{d}{s}
        \\
    ++ "  Status:  {s}\x1b[1m{s}\x1b[0m" ++
        \\
        \\
    , .{
        summary_color,
        "\x1b[0m", // Reset color after the box
        tests_ran,
        "\x1b[32m", tests_passed, "\x1b[0m", // Always green
        if (tests_failed > 0) "\x1b[31m" else "\x1b[90m", tests_failed, "\x1b[0m", // Red if >0, else grey
        if (tests_skiped > 0) "\x1b[33m" else "\x1b[90m", tests_skiped, "\x1b[0m", // Yellow if >0, else grey
        summary_color,                                    status_msg,
    });

    try writer.flush();
}
