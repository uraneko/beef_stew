const std = @import("std");
const Io = std.Io;

const beef_stew = @import("beef_stew");

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    //
    // var buffer: ?[][]u8 = null;
    // const size = 6;
    // for (0..size) |idx| {
    //     if (buffer == null) {
    //         buffer = try allocator.alloc([]u8, 1);
    //     }
    //     if (buffer.?.len == idx) {
    //         buffer = try allocator.realloc(buffer.?, idx + 1);
    //     }
    //
    //     std.debug.print("{d}-{d}: -> {any}\n", .{ idx, buffer.?.len, @TypeOf(buffer) });
    //     buffer.?[idx] = try allocator.alloc(u8, 8);
    //     defer allocator.free(buffer.?[idx]);
    // }
    // _ = .{init};
    // defer allocator.free(buffer.?);

    // for (0..buffer.len) |i| {
    //     // buffer[i] = "str";
    //     std.debug.print("{d}-{d}: -> {any}\n", .{ i, buffer[i].len, @TypeOf(buffer[i]) });
    //     buffer[i] = try allocator.alloc(u8, 16);
    //     std.debug.print("{d}-{d}: -> {any}\n", .{ i, buffer[i].len, @TypeOf(buffer[i]) });
    //     defer allocator.free(buffer[i]);
    // }

    // _ = try std.Io.File.stdin().readStreaming(init.io, buffer);
    // _ = try std.Io.File.stdout().writeStreamingAll(init.io, buffer[0]);
    // std.debug.print("{any}\n", .{buffer});

    var args = std.process.Args.iterate(init.args);
    defer args.deinit();

    const parsed = try parse_args(&args, allocator);
    defer allocator.free(parsed.?);

    if (parsed == null) return;

    // std.debug.print("{any}", .{chunks});
    const stew = try Stew.parse(parsed.?);
    // std.debug.print("Stew{any}", .{stew});
    // defer allocator.destry(stew);

    stew.run();

    // _ = args.next();
    // if (args.next()) |arg| {
    //     std.debug.print("{s}", .{arg});
    // }
}

fn parse_args(args: *std.process.Args.Iterator, allocator: std.mem.Allocator) !?[][:0]const u8 {
    var meat: ?[][:0]const u8 = null;

    _ = args.next();
    while (args.next()) |arg| {
        if (meat == null) {
            meat = try allocator.alloc([:0]const u8, 1);
        } else {
            meat = try allocator.realloc(meat.?, meat.?.len + 1);
        }

        // std.debug.print("{d}: {s}\n", .{ meat.?.len, arg });

        // var chunk = try allocator.alloc(u8, arg.len);
        // defer allocator.free(chunk);
        // chunk = arg;
        // meat.?[len] = try allocator.alloc([:0]const u8, 1);

        // _ = arg;
        meat.?[meat.?.len - 1] = arg;

        // defer allocator.free(meat.?[len]);
    }

    return meat;
}

const StewError = error{
    InvalidCommandArgs,
};

const Stew = struct {
    help_: bool = false,
    env_: bool = false,

    fn parse(args: ?[][:0]const u8) !Stew {
        var stew = Stew{};
        if (args) |chunks| {
            for (chunks) |chunk| {
                // std.debug.print("{any}", .{chunk});
                if (std.mem.eql(u8, chunk, "help") or std.mem.eql(u8, chunk, "h")) {
                    stew.help_ = true;
                } else if (std.mem.eql(u8, chunk, "e") or std.mem.eql(u8, chunk, "env")) {
                    stew.env_ = true;
                }
            }

            return stew;
        }

        return StewError.InvalidCommandArgs;
    }

    fn help() void {
        // const stdout = std.Io.File.stdout();
        // try std.Io.File.enableAnsiEscapeCodes(stdout, io);
        // try stdout.writeStreamingAll(io, help_msg);
        // try stdout.writeStreamingAll(io, "\x1b[1;38;2;213;123;76mthis text is styled and that is all\x1b[0m");
        std.debug.print("\x1b[3;35mREADME.md editor/manager\x1b[0m\n{s}{s}{s}\n{s}Commands:{s}\n{s}{s}\n{s}\n{s}\n{s}{s}Flags:{s}\n{s}{s}\n{s}\n{s}\n{s}{s}", .{ orange_bold, "Usage: stew [Command] [Flags]", clear, orange_bold, clear, light_green, "  help, h         print this help message", "  env, e          prints out the env data: `Lang - Package Manager`,", "                      if the cwd is a programming repo", clear, orange_bold, clear, light_green, " --verbose, -V    prints the full env data, including", "                      the language compiler & package manager versions,", "                      as well as the type of the program: `binary | library`", " --json, -J       prints the env data as json", clear });
    }

    fn env(verbose: bool) void {
        _ = verbose;
    }

    fn run(self: Stew) void {
        if (self.help_) {
            Stew.help();
        }
    }
};

const orange_bold = "\x1b[1;38;2;213;123;76m";
const light_green = "\x1b[35m";
const clear = "\x1b[0m";

const help_msg =
    \\ README.md editor/manager
    \\ Usage: stew [COMMAND] [FLAGS]
    \\ 
    \\ Commands: 
    \\  help, h         print this help message
    \\  env, e          prints out the env data: `Lang - Package Manager`, 
    \\                      if the cwd is a programming repo 
    \\
    \\ Flags: 
    \\ --verbose, -V    prints the full env data, including 
    \\                      the language compiler & package manager versions, 
    \\                      as well as the type of the program: `binary | library`
    \\ --json, -J       prints the env data as json 
;
