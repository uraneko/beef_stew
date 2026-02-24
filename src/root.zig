//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

const STEW_PATH = "forge/zig/beef_stew/";
const DATA_PATH = STEW_PATH ++ "data/main.db3";

pub const Error = error{
    FailedToReadRepoName,
    ArgsAreEmpty,
    UnrecognizableEnvironment,
    FailedToConnectToDB,
    FailedToGetHomeEnvVar,
};

pub fn gen_env_map(allocator: std.mem.Allocator) !std.process.Environ.Map {
    return std.process.Environ.Map.init(allocator);
}

/// sets up this program's environment if it doesn't exist
// TODO this should be in a build step
// should relocate it there, once i know my way around zig better
pub fn setup_environment(
    io: Io,
    env_map: *std.process.Environ.Map,
    allocator: std.mem.Allocator,
) !void {
    var home: []const u8 = undefined;

    if (env_map.get("HOME")) |v| {
        home = v;
    } else {
        return Error.FailedToGetHomeEnvVar;
    }

    const path = try std.mem.concat(allocator, u8, &[3][]const u8{
        home,
        "/",
        STEW_PATH,
    });
    defer allocator.free(path);

    const dir = try std.Io.Dir.openDirAbsolute(io, path, .{
        .iterate = true,
    });
    defer dir.close(io);

    var no_data = true;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .directory and std.mem.eql(u8, entry.name, "data")) {
            no_data = false;
        }
    }

    if (no_data) {
        try dir.createDir(io, "data", Io.File.Permissions.default_dir);
    }
}

pub fn connect_to_db() !c.sqlite {
    var db: *c.sqlite = undefined;
    const res = c.sqlite3_open(&DATA_PATH, &db);

    if (res != 0) {
        return Error.FailedToConnectToDB;
    }

    return db;
}
