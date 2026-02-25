//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const c = @cImport({
    @cInclude("sqlite3.h");
});
pub const sqlite = @import("./sqlite.zig");

pub const STEW_PATH = "forge/zig/beef_stew/";
pub const DATA_PATH = "data/main.db3";

pub const Error = error{
    FailedToReadRepoName,
    ArgsAreEmpty,
    UnrecognizableEnvironment,
    FailedToConnectToDB,
    FailedToGetHomeEnvVar,
};

pub fn init_env(
    allocator: std.mem.Allocator,
    io: std.Io,
    map: *std.process.Environ.Map,
) !void {
    const home = try get_home_env_var(map);

    const path = try std.mem.concat(
        allocator,
        u8,
        &[3][]const u8{ home, "/", STEW_PATH },
    );
    defer allocator.free(path);

    try setup_data_dir(io, path);
    const data_path = try std.mem.concat(
        allocator,
        u8,
        &[3][]const u8{ path, "/", DATA_PATH },
    );
    defer allocator.free(data_path);

    var db = try sqlite.connect(data_path);
    db = null;
    defer sqlite.close(db);
}

pub fn get_home_env_var(map: *std.process.Environ.Map) ![]const u8 {
    if (map.get("HOME")) |v| {
        return v;
    } else {
        return Error.FailedToGetHomeEnvVar;
    }
}

/// sets up this program's environment if it doesn't exist
// TODO this should be in a build step
// should relocate it there, once i know my way around zig better
pub fn setup_data_dir(
    io: Io,
    path: []const u8,
) !void {
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

pub fn setup_database() !void {}
