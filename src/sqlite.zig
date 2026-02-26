const std = @import("std");
const root = @import("./root.zig");
const c = root.c;
const String = root.String;
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

/// updates the db state/contents
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

pub fn fetch() void {}

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

pub const SqliteVal = union(enum) {
    text: struct { [*c]const u8 },
    blob: struct { []const u8 },
    int: struct { i128 },
    real: struct { f64 },
    null,
};

pub const StatementConstructor = struct {
    table: []const u8,
    rows: std.AutoHashMap([]const u8, SqliteVal),

    fn init(table: []const u8, allocator: std.mem.Allocator) !@This() {
        return .{
            .table = table,
            .rows = try .init(allocator),
        };
    }

    fn deinit(self: *@This()) void {
        self.*.rows.deinit();
    }

    fn text(self: *@This(), col: []const u8, val: anytype) !void {
        if (@TypeOf(val) != []const u8) {
            return Error.ValueTypeMismatch;
        }
        const cstr: [*c]const u8 = @ptrCast(val);
        self.*.rows.put(col, SqliteVal.text{cstr});
    }

    fn blob(self: *@This(), col: []const u8, val: anytype) !void {
        if (@TypeOf(val) != []const u8) {
            return Error.ValueTypeMismatch;
        }
        self.*.rows.put(col, SqliteVal.blob{val});
    }

    fn int(self: *@This(), col: []const u8, val: anytype) !void {
        const value = switch (@TypeOf(val)) {
            u8 | u16 | u32 | u64 | u128 | i8 | i16 | i32 | i64 => try std.math.cast(i128, val),
            i128 => val,
            else => return Error.ValueTypeMismatch,
        };

        self.*.rows.put(col, SqliteVal.int{value});
    }

    fn real(self: *@This(), col: []const u8, val: anytype) !void {
        const value = switch (@TypeOf(val)) {
            f32 | f128 => try std.math.cast(f64, val),
            f64 => val,
            else => return Error.ValueTypeMismatch,
        };

        self.*.rows.put(col, SqliteVal.real{value});
    }

    fn null_(
        self: *@This(),
        col: []const u8,
    ) !void {
        self.*.rows.put(col, SqliteVal.null);
    }

    fn build_query(self: *@This(), allocator: std.mem.Allocator) String {
        var query = String.init(allocator, 4096);
        query.extend("insert into ");
        query.extend(self.*.table);
        query.extend(" (");

        var iter = self.*.rows.keyIterator();
        while (try iter.next()) |key| {
            query.extend(key);
            query.extend(", ");
        }
        _ = query.pop_index(2);
        query.extend(") values(");

        for (0..self.*.rows.len) |idx| {
            _ = idx;
            query.extend("?, ");
        }
        _ = query.pop_index(2);

        return query;
    }

    fn extract_bindings(self: *@This(), allocator: std.mem.Allocator) []SqliteVal {
        var slice = allocator.alloc(SqliteVal, self.*.rows.len);
        var iter = self.*.rows.valIterator();
        var idx = 0;
        while (try iter.next()) |val| {
            slice[idx] = val;
            idx += 1;
        }

        return slice;
    }

    pub fn statement(self: *@This(), allocator: std.mem.Allocator) Statement {
        return .{
            .query = self.build_query(allocator),
            .bindings = self.extract_bindings(allocator),
            .stmt = undefined,
        };
    }
};

pub const Statement = struct {
    query: String,
    bindings: []SqliteVal,
    idx: usize,
    stmt: ?*c.sqlite3_stmt,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) u8 {
        self.*.query.deinit(allocator);
        allocator.free(self.*.bindings);

        return c.sqlite3_finalize(self.*.stmt);
    }

    pub fn update_bindings(self: *@This(), bindings: []SqliteVal) void {
        self.*.bindings = bindings;
    }

    pub fn prepare(self: *@This(), db: ?*c.sqlite3) !void {
        if (c.SQLITE_OK != c.sqlite3_prepare_v2(
            db,
            self.*.query,
            self.*.query.len + 1,
            &self.stmt,
            null,
        )) {
            return Error.FailedToPrepareSqliteStatement;
        }
    }

    pub fn bind(self: *Statement) !void {
        const bind_op = switch (self.*.bindings[self.*.idx]) {
            .text => |t| c.sqlite3_bind_text(
                self.*.stmt,
                self.*.idx,
                t,
                t.len,
                c.SQLITE_STATIC,
            ),
            .blob => |b| c.sqlite3_bind_blob(self.*.stmt, self.*.idx, b, b.len, c.SQLITE_STATIC),
            .int => |i| c.sqlite3_bind_int(self.*.stmt, self.*.idx, i),
            .real => |r| c.sqlite3_bind_int(self.*.stmt, self.*.idx, r),
            .null => c.sqlite3_bind_null(self.*.stmt, self.*.idx),
        };
        if (*c.SQLITE_OK != bind_op) {
            return Error.SqliteBindFailed;
        }
        self.*.idx += 1;
    }

    pub fn bind_all(self: *Statement) !void {
        for (0..self.*.bindings.len) |i| {
            _ = i;
            try self.bind();
        }
    }

    pub fn clear() !void {}

    pub fn step() !void {}

    pub fn reset() !void {}
};
