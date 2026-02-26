//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const c = @cImport({
    @cInclude("sqlite3.h");
});
pub const sqlite = @import("./sqlite.zig");
const CreateTable = sqlite.CreateTable;

pub const STEW_PATH = "forge/zig/beef_stew/";
pub const DATA_PATH = "data/main.db3";

pub const Error = error{
    FailedToReadRepoName,
    ArgsAreEmpty,
    UnrecognizableEnvironment,
    FailedToConnectToDB,
    FailedToGetHomeEnvVar,
};

pub fn get_home_env_var(map: *std.process.Environ.Map) ![]const u8 {
    if (map.get("HOME")) |v| {
        return v;
    } else {
        return Error.FailedToGetHomeEnvVar;
    }
}
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

    const db = try sqlite.connect(data_path);
    defer sqlite.close(db);

    try setup_comps_table(db, allocator);
    // try setup_templates_table(db, allocator);
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

pub fn setup_templates_table(db: ?*c.sqlite3, allocator: std.mem.Allocator) !void {
    var create = try CreateTable.init("templates", allocator, 3);
    defer create.deinit(allocator);
    var cols = [_]struct { []const u8, []const u8, bool, bool, bool }{
        .{ "name", "text", true, false, false },
        .{ "value", "text", false, true, true },
        .{ "language", "text", false, false, true },
    };
    try create.columns(&cols);
    try sqlite.update(db, allocator, create);
}

pub fn setup_comps_table(db: ?*c.sqlite3, allocator: std.mem.Allocator) !void {
    var create = try CreateTable.init("components", allocator, 3);
    defer create.deinit(allocator);
    var cols = [_]struct { []const u8, []const u8, bool, bool, bool }{
        .{ "name", "text", true, false, false },
        .{ "value", "text", false, true, true },
        .{ "languages", "int", false, false, true },
    };
    try create.columns(&cols);
    try sqlite.update(db, allocator, create);
}

pub const StrErr = error{
    IndexOutOfBound,
};

pub const String = struct {
    buffer: []u8,
    idx: usize,

    pub fn init(allocator: std.mem.Allocator, size: usize) !@This() {
        return @This(){
            .buffer = try allocator.alloc(u8, size),
            .idx = 0,
        };
    }

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        allocator.free(self.*.buffer);
    }

    pub fn push(self: *String, byte: u8) void {
        self.*.buffer[self.*.idx] = byte;
        self.*.idx += 1;
    }

    pub fn extend(self: *String, bytes: []const u8) void {
        const blen = bytes.len;
        for (self.*.idx..blen + self.*.idx, 0..blen) |sidx, bidx| {
            self.*.buffer[sidx] = bytes[bidx];
        }
        self.*.idx += blen;
    }

    /// walks back self's index by passed amount
    /// doesnt overwrite the walked back buffer[idx] values
    pub fn pop_index(self: *String, amount: usize) !usize {
        if (self.*.idx < amount) {
            return StrErr.IndexOutOfBound;
        }
        self.*.idx -= amount;

        return self.*.idx;
    }

    /// reallocates self's buffer to the amount of bytes that were used
    pub fn shrink_to_size(self: *String, allocator: std.mem.Allocator) !usize {
        if (self.len() == self.*.idx) {
            return 0;
        }
        const diff = self.len() - self.*.idx;
        self.*.buffer = try allocator.realloc(self.*.buffer, self.*.idx);

        return diff;
    }

    pub fn len(self: *const String) usize {
        return self.*.buffer.len;
    }

    pub fn as_str(self: *const String) []const u8 {
        return self.*.buffer[0..self.*.idx];
    }

    pub fn as_cstr(self: *const String) [*c]const u8 {
        const str = self.as_str();

        return @ptrCast(str);
    }
};
