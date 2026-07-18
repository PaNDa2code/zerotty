const std = @import("std");
const builtin = @import("builtin");

const TestStatus = enum { pass, fail, skip };

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, stdin_buffer[0..]);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, stdout_buffer[0..]);

    var server = try std.zig.Server.init(.{
        .in = &stdin_reader.interface,
        .out = &stdout_writer.interface,
        .zig_version = builtin.zig_version_string,
    });

    while (true) {
        const header = try server.receiveMessage();
        switch (header.tag) {
            .query_test_metadata => {
                var string_bytes: std.ArrayList(u8) = .empty;
                defer string_bytes.deinit(init.gpa);

                try string_bytes.append(init.gpa, 0);

                const test_functions = builtin.test_functions;
                const names = try init.gpa.alloc(u32, test_functions.len);
                defer init.gpa.free(names);

                const expected_panic_msgs = try init.gpa.alloc(u32, test_functions.len);
                defer init.gpa.free(expected_panic_msgs);

                for (test_functions, names, expected_panic_msgs) |test_fn, *name, *expected_panic_msg| {
                    name.* = @intCast(string_bytes.items.len);
                    try string_bytes.ensureUnusedCapacity(init.gpa, test_fn.name.len + 1);
                    string_bytes.appendSliceAssumeCapacity(test_fn.name);
                    string_bytes.appendAssumeCapacity(0);
                    expected_panic_msg.* = 0;
                }

                try server.serveTestMetadata(.{
                    .names = names,
                    .expected_panic_msgs = expected_panic_msgs,
                    .string_bytes = string_bytes.items,
                });
            },
            .run_test => {
                std.testing.allocator_instance = .init;
                std.testing.io_instance = .init(std.testing.allocator, .{});

                const test_index = try server.receiveBody_u32();
                const test_func = builtin.test_functions[test_index];

                try server.serveStringMessage(.test_started, "hello test");

                const test_result = test_func.func();

                const TestResults = std.zig.Server.Message.TestResults;
                var status: TestResults.Status = .pass;

                test_result catch |err| {
                    switch (err) {
                        error.SkipZigTest => status = .skip,
                        else => status = .fail,
                    }
                };

                status = .pass;

                std.testing.io_instance.deinit();
                const leak_count = std.testing.allocator_instance.detectLeaks();
                std.testing.allocator_instance.deinitWithoutLeakChecks();

                try server.serveTestResults(.{
                    .index = test_index,
                    .flags = .{
                        .status = status,
                        .fuzz = false,
                        .log_err_count = 1,
                        .leak_count = @intCast(leak_count),
                    },
                });
            },
            .exit => std.process.exit(0),
            else => {
                std.log.err("unimplemnted", .{});
                std.process.exit(1);
            },
        }
    }
}
