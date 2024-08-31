const std = @import("std");

const FnType = *const fn (args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void;

var builtinsHash: std.StringHashMap(FnType) = undefined;

pub fn main() !void {
    builtinsHash = std.StringHashMap(FnType).init(std.heap.page_allocator);
    defer builtinsHash.deinit();

    try builtinsHash.put("cd", &cd);
    try builtinsHash.put("echo", &echo);
    try builtinsHash.put("exit", &exit);
    try builtinsHash.put("pwd", &pwd);
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

        // try executing builtin
        const builtin = builtinsHash.get(command);
        if (builtin) |builtin_func| {
            try builtin_func(&it);
            continue;
        }

        // try executing program in PATH
        const allocator = std.heap.page_allocator;
        const full_path_or_null = try getFullPath(allocator, command);
        if (full_path_or_null) |full_path| {
            defer allocator.free(full_path);

            var args = try allocator.alloc([]const u8, 1);
            defer allocator.free(args);

            args[0] = full_path;
            while (it.next()) |arg| {
                args = try allocator.realloc(args, args.len + 1);
                args[args.len - 1] = arg;
            }

            if (!std.process.can_spawn) {
                return error.CannotSpawn;
            }

            var child = std.process.Child.init(args, allocator);
            _ = try child.spawnAndWait();
            continue;
        }

        // command not found
        try stdout.print("{s}: command not found\n", .{command});
    }
}

fn cd(args_it: *std.mem.SplitIterator(u8, .sequence)) !void {
    const stderr = std.io.getStdErr().writer();

    const path_arg = args_it.next() orelse "";
    std.process.changeCurDir(path_arg) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("cd: {s}: No such file or directory\n", .{path_arg});
        },
        error.NotDir => {
            try stderr.print("cd: {s}: Not a directory\n", .{path_arg});
        },
        else => {
            return err;
        },
    };
}

fn echo(args_it: *std.mem.SplitIterator(u8, .sequence)) !void {
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

fn exit(args_it: *std.mem.SplitIterator(u8, .sequence)) !void {
    var status: u8 = 0;
    const status_arg = args_it.next() orelse "";
    status = std.fmt.parseInt(u8, status_arg, 10) catch @as(u8, 0);
    std.process.exit(status);
}

fn pwd(args_it: *std.mem.SplitIterator(u8, .sequence)) !void {
    _ = args_it;

    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    try stdout.print("{s}\n", .{cwd});
}

fn type_(args_it: *std.mem.SplitIterator(u8, .sequence)) !void {
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
    const full_path_or_null = try getFullPath(allocator, arg);
    if (full_path_or_null) |full_path| {
        try stdout.print("{s} is {s}\n", .{ arg, full_path });
        allocator.free(full_path);
    } else {
        try stdout.print("{s}: not found\n", .{arg});
    }
}

fn getFullPath(allocator: std.mem.Allocator, command: []const u8) !?[]const u8 {
    if (command.len == 0) {
        return error.InvalidCommand;
    }

    const env_vars = try std.process.getEnvMap(allocator);
    const path_value = env_vars.get("PATH") orelse "";
    var path_it = std.mem.split(u8, path_value, ":");
    while (path_it.next()) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, command });
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

        return full_path;
    }

    return null;
}
