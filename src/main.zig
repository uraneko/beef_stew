const std = @import("std");
const Io = std.Io;

// const beef_stew = @import("beef_stew");

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

    // std.debug.print(">>> {c}\n", .{std.Io.Dir.path.delimiter});
    const parsed = try parse_args(&args, allocator);

    if (parsed == null) {
        std.debug.print("args cant be null", .{});

        return;
    }
    defer allocator.free(parsed.?);

    // std.debug.print("{any}", .{chunks});
    const stew = try Stew.from_args(parsed.?);
    // std.debug.print("Stew{any}", .{stew});
    // defer allocator.destry(stew);

    var profile: Profile = undefined;
    if (try stew.run(init.io, allocator)) |pf| {
        profile = pf;
    } else return;
    profile.print();
    defer allocator.free(profile._path);

    // std.debug.print("{any}", .{profile});

    // _ = args.next();
    // if (args.next()) |arg| {
    //     std.debug.print("{s}", .{arg});
    // }
}

const err = error{ FailedToReadRepoName, ArgsAreEmpty, UnrecognizableEnvironment };

fn parse_args(args: *std.process.Args.Iterator, allocator: std.mem.Allocator) !?[][:0]const u8 {
    var meat: ?[][:0]const u8 = null;

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

    fn from_args(args: ?[][:0]const u8) !Stew {
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
        std.debug.print("\x1b[3;35mREADME.md editor/manager\x1b[0m\n", .{});
        std.debug.print("{s}{s}{s}\n", .{ orange_bold, "Usage: stew [Command] [Flags]", clear });
        std.debug.print("{s}Commands:{s}\n", .{ orange_bold, clear });
        std.debug.print("{s}{s}\n", .{
            light_green,
            "  help, h         print this help message",
        });
        std.debug.print("{s}\n", .{"  env, e          prints out the env data: `Lang - Package Manager`,"});
        std.debug.print("{s}\n", .{"                      if the cwd is a programming repo"});
        std.debug.print("{s}{s}Flags:{s}\n", .{ clear, orange_bold, clear });
        std.debug.print("{s}{s}\n", .{ light_green, " --verbose, -V    prints the full env data, including" });
        std.debug.print("{s}\n", .{"                      the language compiler & package manager versions,"});
        std.debug.print("{s}\n", .{"                      as well as the type of the program: `binary | library`"});
        std.debug.print("{s}{s}\n", .{ " --json, -J       prints the env data as json", clear });
    }

    fn env(allocator: std.mem.Allocator, io: std.Io, verbose: bool) !Profile {
        _ = verbose;

        const repo = std.Io.Dir.cwd();
        const src = try repo.openDir(io, "src/", .{
            .iterate = true,
        });
        defer src.close(io);

        // name
        // TODO find a way to get the dir name only
        // since i dont actually need the path
        // WARN this fails if path is longer than 64 bytes
        var path = try allocator.alloc(u8, 64);
        const n = try repo.realPathFile(io, ".", path);
        path = try allocator.realloc(path, n);
        const name = std.fs.path.basename(path);

        // language
        var lang: ?Language = null;
        var iter = src.iterate();
        while (try iter.next(io)) |file| {
            for (lang_checks.keys()) |ext| {
                if (std.mem.endsWith(u8, file.name, ext)) {
                    lang = lang_checks.get(ext);
                }
            }
        }
        if (lang == null) return err.UnrecognizableEnvironment;

        // toolchain
        var toolchain: ?Toolchain = null;
        const iterable_repo = try repo.openDir(io, ".", .{ .iterate = true });
        defer iterable_repo.close(io);

        iter = iterable_repo.iterate();
        while (try iter.next(io)) |file| {
            if (toolchain_checks.get(file.name)) |tc| {
                toolchain = tc;
            }
        }
        if (toolchain == null) return err.UnrecognizableEnvironment;

        return Profile{ ._path = path, .name = name, .lang = lang.?, .toolchain = toolchain.? };
    }

    fn run(self: Stew, io: std.Io, allocator: std.mem.Allocator) !?Profile {
        if (self.help_) {
            Stew.help();
        }

        if (self.env_) {
            return try Stew.env(allocator, io, false);
        }

        return null;
    }
};

const Profile = struct {
    _path: []const u8,
    name: []const u8,
    lang: Language,
    toolchain: Toolchain,

    fn print(self: Profile) void {
        std.debug.print("package -> {s}\n", .{self.name});
        std.debug.print("{s}\n", .{self.lang.as_str()});
        std.debug.print("{s}\n", .{self.toolchain.as_str()});
    }
};

const orange_bold = "\x1b[1;38;2;213;123;76m";
const light_green = "\x1b[35m";
const clear = "\x1b[0m";

const lang_checks = std.StaticStringMap(Language).initComptime(.{
    .{ ".rs", .Rust },
    .{ ".zig", .Zig },
    .{ ".idr", .Idris },
    .{ ".gleam", .Gleam },
    .{ ".ts", .Ts },
    .{ "tsx", .Ts },
});

const toolchain_checks = std.StaticStringMap(Toolchain).initComptime(.{
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
    \\                      the language compiler & toolchain versions, 
    \\                      as well as the type of the program: `binary | library`
    \\ --json, -J       prints the env data as json 
;

const Language = enum {
    Rust,
    Zig,
    Gleam,
    Idris,
    Ts,

    fn as_str(lang: Language) []const u8 {
        // if (elf == null) return "language -> ???";

        return switch (lang) {
            .Zig => "language -> zig",
            .Rust => "language -> rust",
            .Gleam => "language -> gleam",
            .Idris => "language -> idris",
            .Ts => "language -> typescript",
        };
    }
};

const Toolchain = enum {
    Cargo,
    Zig,
    Gleam,
    Pack2,
    Npm,
    Pnpm,
    Yarn,
    Bun,

    fn as_str(self: Toolchain) []const u8 {
        // if (elf == null) return "toolchain -> ???";

        return switch (self) {
            .Cargo => "toolchain -> cargo",
            .Zig => "toolchain -> zig",
            .Npm => "toolchain -> npm",
            .Pnpm => "toolchain -> pnpm",
            .Yarn => "toolchain -> yarn",
            .Bun => "toolchain -> bun",
            .Gleam => "toolchain -> gleam",
            .Pack2 => "toolchain -> pack2",
        };
    }
};
