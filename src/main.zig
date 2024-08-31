const std = @import("std");

pub fn main() !void {
    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;
        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        var it = std.mem.split(u8, user_input, " ");
        const command = it.next() orelse "";
        if (command.len == 0) {
            continue;
        }

        if (std.mem.eql(u8, command, "exit")) {
            const status_arg = it.next() orelse "";
            const status = std.fmt.parseInt(u8, status_arg, 10) catch @as(u8, 0);
            std.process.exit(status);
        } else if (std.mem.eql(u8, command, "echo")) {
            var is_first_arg = true;
            while (it.next()) |arg| {
                if (!is_first_arg) {
                    try stdout.print(" ", .{});
                } else {
                    is_first_arg = false;
                }

                try stdout.print("{s}", .{arg});
            }

            try stdout.print("\n", .{});
            continue;
        }

        try stdout.print("{s}: command not found\n", .{command});
    }
}
