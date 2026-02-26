const std = @import("std");
const root = @import("./root.zig");
const c = root.c;
const err = root.Error;
pub const CreateTable = @import("sqlite/create.zig").CreateTable;

pub fn connect(path: []const u8) !?*c.sqlite3 {
    const c_path: [*c]const u8 = @ptrCast(path);
    var db: ?*c.sqlite3 = undefined;
    if (c.SQLITE_OK != c.sqlite3_open(c_path, &db)) {
        return err.FailedToConnectToDB;
    }

    return db;
}

pub fn close(db: ?*c.sqlite3) void {
    defer _ = c.sqlite3_close(db);
}

/// sqlite3_exec
/// calling it update because using this successfully always updates the db state/contents
pub fn update(
    db: ?*c.sqlite3,
    allocator: std.mem.Allocator,
    operation: anytype,
) !void {
    // const act = std.meta.stringToEnum(Action, operation.action()) orelse unreachable;
    switch (@TypeOf(operation)) {
        CreateTable => try operation.create(db, allocator),
        else => unreachable,
    }
}

pub const Error = error{
    TableNameTypeCantBeUndefined,
    PKConstraintCantCoexistWithUnique,
    SqliteExecFailed,
};

// pub const Column = union(enum) {
//     Parameterized: Column,
//     KeyVal: struct { key: []const u8, val: []const u8 },
// };

pub const SqliteType = enum {
    text,
    blob,
    int,
    real,
    null,

    pub fn as_str(self: SqliteType) []const u8 {
        return switch (self) {
            .text => "text",
            .blob => "blob",
            .int => "integer",
            .real => "real",
            .null => "null",
        };
    }
};
