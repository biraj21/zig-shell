const std = @import("std");

const FnType = *const fn (args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void;

var builtinsHash: std.StringHashMap(FnType) = undefined;

pub fn main() !void {
    builtinsHash = std.StringHashMap(FnType).init(std.heap.page_allocator);
    defer builtinsHash.deinit();

    try builtinsHash.put("echo", &echo);
    try builtinsHash.put("exit", &exit);
    try builtinsHash.put("type", &type_);

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

        const builtin = builtinsHash.get(command);
        if (builtin) |builtin_func| {
            try builtin_func(&it);
            continue;
        }

        try stdout.print("{s}: command not found\n", .{command});
    }
}

fn echo(args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void {
    const stdout = std.io.getStdOut().writer();

    var is_first_arg = true;
    while (args_it.next()) |arg| {
        if (!is_first_arg) {
            try stdout.print(" ", .{});
        } else {
            is_first_arg = false;
        }

        try stdout.print("{s}", .{arg});
    }

    try stdout.print("\n", .{});
}

fn exit(args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void {
    var status: u8 = 0;
    const status_arg = args_it.next() orelse "";
    status = std.fmt.parseInt(u8, status_arg, 10) catch @as(u8, 0);
    std.process.exit(status);
}

fn type_(args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    const arg = args_it.next() orelse "";
    if (arg.len == 0) {
        return;
    }

    if (builtinsHash.contains(arg)) {
        try stdout.print("{s} is a shell builtin\n", .{arg});
        return;
    }

    const allocator = std.heap.page_allocator;
    const env_vars = try std.process.getEnvMap(allocator);
    const path_value = env_vars.get("PATH") orelse "";
    var path_it = std.mem.split(u8, path_value, ":");
    while (path_it.next()) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, arg });
        defer allocator.free(full_path);

        const file = std.fs.openFileAbsolute(full_path, .{ .mode = .read_only }) catch {
            continue;
        };
        defer file.close();

        const mode = file.mode() catch {
            continue;
        };

        const is_executable = mode & 0b001 != 0;
        if (!is_executable) {
            continue;
        }

        try stdout.print("{s} is {s}\n", .{ arg, full_path });
        return;
    }

    try stdout.print("{s}: not found\n", .{arg});
}
