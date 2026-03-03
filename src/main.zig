const std = @import("std");
const Io = std.Io;

const root = @import("./root.zig");
const Select = root.Select;
const SqliteVal = root.SqliteVal;
const c = root.c;
const err = root.Error;

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try root.init_env(allocator, init.io, init.environ_map);

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

    var envr: Envr = undefined;
    if (try stew.run(init.io, allocator)) |env| {
        envr = env;
    } else return;
    defer allocator.free(envr._path);

    try envr.run(&stew, init.io, allocator, init.environ_map);

    // std.debug.print("{any}", .{env});

    // _ = args.next();
    // if (args.next()) |arg| {
    //     std.debug.print("{s}", .{arg});
    // }
}

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
    env_: bool = true,
    init_: bool = false,

    fn from_args(args: ?[][:0]const u8) !Stew {
        var stew = Stew{};
        if (args) |chunks| {
            for (chunks) |chunk| {
                // std.debug.print("{any}", .{chunk});
                if (std.mem.eql(u8, chunk, "help") or std.mem.eql(u8, chunk, "h")) {
                    stew.help_ = true;
                } else if (std.mem.eql(u8, chunk, "i") or std.mem.eql(u8, chunk, "init")) {
                    stew.init_ = true;
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
        std.debug.print(
            "\x1b[3;38;2;112;114;154mreadme markdown files editor/manager\x1b[0m\n",
            .{},
        );
        std.debug.print("{s}{s}{s}\n", .{ orange_bold, "Usage: stew [Command] [Flags]", clear });
        std.debug.print("{s}Commands:{s}\n", .{ orange_bold, clear });
        std.debug.print("{s}{s}\n", .{
            light_green,
            "  help, h         print this help message",
        });
        std.debug.print("{s}\n", .{
            "  env, e          prints out the env data { package name, language, toolchain },",
        });
        std.debug.print("{s}\n", .{"                      if the cwd is a programming repo"});
        std.debug.print("{s}\n", .{
            "  init, i         initializes a new README.md file in the current dir,",
        });
        std.debug.print("{s}\n", .{
            "                      does nothing if the file already exists",
        });
        std.debug.print("{s}{s}Flags:{s}\n", .{ clear, orange_bold, clear });
        std.debug.print("{s}{s}\n", .{
            light_green,
            " --verbose, -V    prints the full env data, including",
        });
        std.debug.print("{s}\n", .{
            "                      the language compiler & package manager versions,",
        });
        std.debug.print("{s}\n", .{
            "                      as well as the type of the program: `binary | library`",
        });
        std.debug.print("{s}{s}\n", .{ " --json, -J       prints the env data as json", clear });
    }

    fn env(allocator: std.mem.Allocator, io: std.Io, verbose: bool) !Envr {
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

        // WARN allocating less than 4096 bytes
        // triggers this error when using path
        //  if (out_buffer.len < posix.PATH_MAX) return error.NameTooLong;
        // from '.../lib/std/Io/Threaded.zig:6638:46'
        var path = try allocator.alloc(u8, 4096);
        const n = try repo.realPathFile(io, ".", path);
        if (n < 64) {
            path = try allocator.realloc(path, n);
        }
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

        var contains_readme = false;
        iter = iterable_repo.iterate();
        while (try iter.next(io)) |file| {
            if (std.mem.eql(u8, file.name, "README.md")) {
                contains_readme = true;
            } else if (toolchain_checks.get(file.name)) |tc| {
                toolchain = tc;
            }
        }
        if (toolchain == null) return err.UnrecognizableEnvironment;

        return Envr{ .contains_readme = contains_readme, ._path = path, .package = name, .lang = lang.?, .toolchain = toolchain.? };
    }

    /// creates a new README.md file in the current repo
    /// from the language template in the main database
    fn run(self: Stew, io: std.Io, allocator: std.mem.Allocator) !?Envr {
        if (self.help_) {
            Stew.help();
            return null;
        }

        return try Stew.env(allocator, io, false);
    }
};

const Envr = struct {
    _path: []const u8,
    contains_readme: bool,
    package: []const u8,
    lang: Language,
    toolchain: Toolchain,

    fn print(self: *const Envr) void {
        std.debug.print("package   -> {s}\n", .{self.package});
        std.debug.print("language  -> {s}\n", .{self.lang.as_str()});
        std.debug.print("toolchain -> {s}\n", .{self.toolchain.as_str()});
        std.debug.print("readme?   -> {any}\n", .{self.contains_readme});
    }

    fn run(
        self: Envr,
        stew: *const Stew,
        io: std.Io,
        allocator: std.mem.Allocator,
        map: *std.process.Environ.Map,
    ) !void {
        if (stew.init_) {
            return self.init(io, allocator, map);
        }

        self.print();
    }

    fn init(
        self: *const Envr,
        io: std.Io,
        allocator: std.mem.Allocator,
        map: *std.process.Environ.Map,
    ) !void {
        if (self.contains_readme) {
            std.debug.print("README.md already exists", .{});

            return;
        }
        const comps = try fetch_comps(allocator, map);
        defer {
            SqliteVal.free_texts(comps, allocator);
            allocator.free(comps);
        }
        const comp = switch (comps[0]) {
            .text => |t| t,
            else => unreachable,
        };
        // TODO slect and fetch have been fixed
        // but parsing and writing components is yet to be finalized
        const re_size = std.mem.replacementSize(u8, comp, "{title}", self.package);
        const title = try allocator.alloc(u8, re_size);
        defer allocator.free(title);
        _ = std.mem.replace(u8, comp, "{title}", self.package, title);
        const repo = std.Io.Dir.cwd();

        var file = try repo.createFile(io, "README.md", .{
            .truncate = false,
            .exclusive = true,
        });
        try file.writePositionalAll(io, title, 0);
    }
};

const orange_bold = "\x1b[1;38;2;213;123;76m";
const light_green = "\x1b[38;2;131;142;153m";
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

const Language = enum {
    Rust,
    Zig,
    Gleam,
    Idris,
    Ts,

    fn as_str(lang: Language) []const u8 {
        // if (elf == null) return "???";

        return switch (lang) {
            .Zig => "zig",
            .Rust => "rust",
            .Gleam => "gleam",
            .Idris => "idris",
            .Ts => "typescript",
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
        // if (elf == null) return "???";

        return switch (self) {
            .Cargo => "cargo",
            .Zig => "zig",
            .Npm => "npm",
            .Pnpm => "pnpm",
            .Yarn => "yarn",
            .Bun => "bun",
            .Gleam => "gleam",
            .Pack2 => "pack2",
        };
    }
};

fn fetch_comps(
    allocator: std.mem.Allocator,
    map: *std.process.Environ.Map,
) ![]SqliteVal {
    var value_column = [1][]const u8{"value"};
    var select = Select.init("components", &value_column);

    select.where("name = 'title'");
    // try select.condition("name", "license");
    // select.operator("or");
    const home = try root.get_home_env_var(map);
    const path = try std.mem.concat(allocator, u8, &[5][]const u8{
        home, "/", root.STEW_PATH, "/", root.DATA_PATH,
    });
    defer allocator.free(path);
    const db = try root.sqlite.connect(path);
    defer _ = root.sqlite.close(db);

    return try select.select(db, allocator, 1);
}
