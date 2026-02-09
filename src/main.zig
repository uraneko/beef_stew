const std = @import("std");
const Io = std.Io;

const beef_stew = @import("beef_stew");

pub fn main(init: std.process.Init) !void {
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

    var args = std.process.Args.iterate(init.minimal.args);
    defer args.deinit();

    const parsed = try parse_args(&args, allocator);

    if (parsed == null) {
        std.debug.print("args cant be null", .{});

        return;
    }
    defer allocator.free(parsed.?);

    // std.debug.print("{any}", .{chunks});
    const stew = try Stew.parse(parsed.?);
    // std.debug.print("Stew{any}", .{stew});
    // defer allocator.destry(stew);

    try stew.run(init.io);

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
        std.debug.print("\x1b[3;35mREADME.md editor/manager\x1b[0m\n{s}{s}{s}\n{s}Commands:{s}\n{s}{s}\n{s}\n{s}\n{s}{s}Flags:{s}\n{s}{s}\n{s}\n{s}\n{s}{s}\n", .{ orange_bold, "Usage: stew [Command] [Flags]", clear, orange_bold, clear, light_green, "  help, h         print this help message", "  env, e          prints out the env data: `Lang - Package Manager`,", "                      if the cwd is a programming repo", clear, orange_bold, clear, light_green, " --verbose, -V    prints the full env data, including", "                      the language compiler & package manager versions,", "                      as well as the type of the program: `binary | library`", " --json, -J       prints the env data as json", clear });
    }

    fn env(io: std.Io, verbose: bool) !void {
        _ = verbose;

        const repo = std.Io.Dir.cwd();
        var lang: ?EnvLang = null;
        const src = try repo.openDir(io, "src/", .{
            .iterate = true,
        });
        defer src.close(io);
        var iter = src.iterate();
        while (try iter.next(io)) |file| {
            for (lang_checks.keys()) |ext| {
                if (std.mem.endsWith(u8, file.name, ext)) {
                    lang = lang_checks.get(ext);
                }
            }

            // std.debug.print("{s} ({any})\n", .{ file.name, file.kind });
        }
        // package manager
        var pacman: ?EnvPackageManager = null;
        const iterable_repo = try repo.openDir(io, ".", .{ .iterate = true });
        defer iterable_repo.close(io);

        iter = iterable_repo.iterate();
        while (try iter.next(io)) |file| {
            if (pacman_checks.get(file.name)) |package_manager| {
                pacman = package_manager;
            }
        }

        std.debug.print("{s}{s}", .{ EnvLang.as_str(lang), EnvPackageManager.as_str(pacman) });
    }

    fn run(self: Stew, io: std.Io) !void {
        if (self.help_) {
            Stew.help();

            return;
        }

        if (self.env_) {
            try Stew.env(io, false);
        }
    }
};

const orange_bold = "\x1b[1;38;2;213;123;76m";
const light_green = "\x1b[35m";
const clear = "\x1b[0m";

const lang_checks = std.StaticStringMap(EnvLang).initComptime(.{
    .{ ".rs", .Rust },
    .{ ".zig", .Zig },
    .{ ".idr", .Idris },
    .{ ".gleam", .Gleam },
    .{ ".ts", .Ts },
    .{ "tsx", .Ts },
});

const pacman_checks = std.StaticStringMap(EnvPackageManager).initComptime(.{
    .{ "package.json", .Npm },
    .{ "pnpm-lock.yaml", .Pnpm },
    .{ "yarn.lock", .Yarn },
    .{ "bun.lock", .Bun },
    .{ "Cargo.toml", .Cargo },
    .{ "build.zig", .Zig },
    .{ "gleam.toml", .Gleam },
    .{ "pack.toml", .Pack2 },
});

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

const EnvLang = enum {
    Rust,
    Zig,
    Gleam,
    Idris,
    Ts,

    fn as_str(elf: ?EnvLang) []const u8 {
        if (elf == null) return "language -> ???\n";

        return switch (elf.?) {
            .Zig => "language -> zig\n",
            .Rust => "language -> rust\n",
            .Gleam => "language -> gleam\n",
            .Idris => "language -> idris\n",
            .Ts => "language -> typescript\n",
        };
    }
};

const EnvPackageManager = enum {
    Cargo,
    Zig,
    Gleam,
    Pack2,
    Npm,
    Pnpm,
    Yarn,
    Bun,

    fn as_str(elf: ?EnvPackageManager) []const u8 {
        if (elf == null) return "???";

        return switch (elf.?) {
            .Cargo => "package-manager -> cargo\n",
            .Zig => "package-manager -> zig\n",
            .Npm => "package-manager -> npm\n",
            .Pnpm => "package-manager -> pnpm\n",
            .Yarn => "package-manager -> yarn\n",
            .Bun => "package-manager -> bun\n",
            .Gleam => "package-manager -> gleam\n",
            .Pack2 => "package-manager -> pack2\n",
        };
    }
};
