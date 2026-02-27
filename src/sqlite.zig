const std = @import("std");
const root = @import("./root.zig");
const c = root.c;
const String = root.String;
const err = root.Error;
pub const CreateTable = @import("sqlite/create.zig").CreateTable;
pub const InsertIntoTable = @import("sqlite/insert.zig").InsertIntoTable;

pub fn connect(path: []const u8) !?*c.sqlite3 {
    const c_path: [*c]const u8 = @ptrCast(path);
    var db: ?*c.sqlite3 = undefined;
    if (c.SQLITE_OK != c.sqlite3_open(c_path, &db)) {
        return err.FailedToConnectToDB;
    }

    return db;
}

pub fn sqlerr(db: ?*c.sqlite3) [*c]const u8 {
    return c.sqlite3_errmsg(db);
}

pub fn close(db: ?*c.sqlite3) c_int {
    return c.sqlite3_close(db);
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
        InsertIntoTable => try operation.insert(db, allocator),
        else => unreachable,
    }
}

pub fn fetch() void {}

pub const Error = error{
    SqliteBindFailed,
    FailedAtStep,
    FailedToPrepareSqliteStatement,
    ValueTypeMismatch,
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
    text: [*c]const u8,
    blob: ?*const anyopaque,
    int: i128,
    real: f64,
    null,
};

pub const StatementConstructor = struct {
    table: []const u8,
    rows: std.StringHashMap(SqliteVal),

    pub fn init(table: []const u8, allocator: std.mem.Allocator) !@This() {
        return .{
            .table = table,
            .rows = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.*.rows.deinit();
    }

    pub fn text(self: *@This(), col: []const u8, val: anytype) !void {
        const len = val.len;
        // @compileLog(@TypeOf(val) == *const [len:0]u8);
        if (@TypeOf(val) != *const [len:0]u8) {
            return Error.ValueTypeMismatch;
        }
        const cstr: [*c]const u8 = @ptrCast(val);
        try self.*.rows.put(col, SqliteVal{ .text = cstr });
    }

    pub fn blob(self: *@This(), col: []const u8, val: anytype) !void {
        if (@TypeOf(val) != []const u8) {
            return Error.ValueTypeMismatch;
        }
        try self.*.rows.put(col, SqliteVal{ .blob = val });
    }

    pub fn int(self: *@This(), col: []const u8, val: anytype) !void {
        // @compileLog(@TypeOf(val));
        const value = switch (@TypeOf(val)) {
            u8,
            u16,
            u32,
            u64,
            u128,
            i8,
            i16,
            i32,
            i64,
            comptime_int,
            => std.math.cast(i128, val).?,
            i128 => val,
            else => return Error.ValueTypeMismatch,
        };

        try self.*.rows.put(col, SqliteVal{ .int = value });
    }

    pub fn real(self: *@This(), col: []const u8, val: anytype) !void {
        const value = switch (@TypeOf(val)) {
            f32, f128 => try std.math.cast(f64, val),
            f64 => val,
            else => return Error.ValueTypeMismatch,
        };

        try self.*.rows.put(col, SqliteVal{ .real = value });
    }

    pub fn null_(
        self: *@This(),
        col: []const u8,
    ) !void {
        try self.*.rows.put(col, SqliteVal{.null});
    }

    fn gen_stmt_vals(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) !struct { String, []SqliteVal } {
        const count = self.*.rows.count();
        var keys = self.*.rows.keyIterator();

        var query = try String.init(allocator, 4096);
        query.extend("insert into ");
        query.extend(self.*.table);
        query.extend(" (");

        var slice = try allocator.alloc(SqliteVal, count);
        var idx: usize = 0;

        while (keys.next()) |key| {
            const row = self.*.rows.fetchRemove(key.*);
            query.extend(row.?.key);
            query.extend(", ");

            slice[idx] = row.?.value;
            idx += 1;
        }
        _ = try query.pop_index(2);
        query.extend(") values(");

        for (0..count) |i| {
            const bind_idx = 48 + i + 1;
            query.push('?');
            query.push(@intCast(bind_idx));
            if (i < count - 1) {
                query.extend(", ");
            }
        }
        query.extend(");");

        return .{ query, slice };
    }

    pub fn statement(self: *@This(), allocator: std.mem.Allocator) !Statement {
        const query, const bindings = try self.gen_stmt_vals(allocator);
        return .{
            .query = query,
            .bindings = bindings,
            .stmt = undefined,
            .errmsg = undefined,
            .idx = 0,
        };
    }
};

pub const Statement = struct {
    query: String,
    bindings: []SqliteVal,
    idx: usize,
    errmsg: [*c]const u8,
    stmt: ?*c.sqlite3_stmt,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) c_int {
        self.*.query.deinit(allocator);
        allocator.free(self.*.bindings);

        return c.sqlite3_finalize(self.*.stmt);
    }

    pub fn update_bindings(
        self: *@This(),
        allocator: std.mem.Allocator,
        bindings: []SqliteVal,
    ) void {
        defer allocator.free(self.*.bindings);
        self.*.bindings = bindings;
    }

    pub fn catch_error(self: *@This(), db: ?*c.sqlite3) void {
        self.*.errmsg = c.sqlite3_errmsg(db);
    }

    pub fn prepare(self: *@This(), db: ?*c.sqlite3) !void {
        std.debug.print("{s}\n", .{self.*.query.as_str()});
        if (c.SQLITE_OK != c.sqlite3_prepare_v2(
            db,
            self.*.query.as_cstr(),
            @intCast(self.*.query.len() + 1),
            &self.stmt,
            null,
        )) {
            self.catch_error(db);
            std.debug.print(">{s}<\n", .{self.errmsg});
            return Error.FailedToPrepareSqliteStatement;
        }
    }

    pub fn bind(self: *Statement, db: ?*c.sqlite3) !void {
        const c_idx: c_int = @intCast(self.*.idx + 1);
        const bind_op = switch (self.*.bindings[self.*.idx]) {
            .text => |t| c.sqlite3_bind_text(
                self.*.stmt,
                c_idx,
                t,
                @intCast(std.mem.len(t)),
                c.SQLITE_STATIC,
            ),
            // WARN this is broken for now
            // dont use blobs
            .blob => |b| c.sqlite3_bind_blob(
                self.*.stmt,
                c_idx,
                b,
                0,
                // @intCast(std.mem.len(std.mem.asBytes(b))),
                c.SQLITE_STATIC,
            ),
            .int => |i| c.sqlite3_bind_int(self.*.stmt, c_idx, @intCast(i)),
            .real => |r| c.sqlite3_bind_int(self.*.stmt, c_idx, @intFromFloat(r)),
            .null => c.sqlite3_bind_null(self.*.stmt, c_idx),
        };
        if (c.SQLITE_OK != bind_op) {
            self.catch_error(db);
            std.debug.print(">{s}<\n", .{self.errmsg});
            return Error.SqliteBindFailed;
        }
        self.*.idx += 1;
    }

    pub fn bind_all(self: *Statement, db: ?*c.sqlite3) !void {
        for (0..self.*.bindings.len) |i| {
            _ = i;
            try self.bind(db);
        }
    }

    pub fn step(self: *Statement) !void {
        if (c.SQLITE_DONE != c.sqlite3_step(self.*.stmt)) {
            return Error.FailedAtStep;
        }
    }

    pub fn reset(self: *@This()) void {
        _ = c.sqlite3_reset(self.*.stmt);
    }
};
