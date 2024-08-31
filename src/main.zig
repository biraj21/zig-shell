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
            std.os.exit(status);
        }

        try stdout.print("{s}: command not found\n", .{command});
    }
}
