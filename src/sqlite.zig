const std = @import("std");
const root = @import("./root.zig");
const c = root.c;
const String = root.String;
const err = root.Error;
pub const CreateTable = @import("sqlite/create.zig").CreateTable;
pub const InsertIntoTable = @import("sqlite/insert.zig").InsertIntoTable;
pub const Select = @import("sqlite/select.zig").Select;

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
    InvalidSqliteTypeValue,
    InvalidTypeValCombi,
    BadTypeForOperation,
};

// pub const Column = union(enum) {
//     Parameterized: Column,
//     KeyVal: struct { key: []const u8, val: []const u8 },
// };

pub fn is_int(num_ty: type) bool {
    return switch (num_ty) {
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
        c_int,
        c_uint,
        => true,
        else => false,
    };
}

pub fn is_float(flt_ty: type) bool {
    return switch (flt_ty) {
        f32, f64, f128 => true,
        else => false,
    };
}

pub const SqliteType = enum(u8) {
    text = 3,
    blob = 4,
    int = 1,
    real = 2,
    null = 5,

    pub fn as_str(self: *const SqliteType) []const u8 {
        return switch (self.*) {
            .text => "text",
            .blob => "blob",
            .int => "integer",
            .real => "real",
            .null => "null",
        };
    }

    // the int values are found at https://sqlite.org/c3ref/c_blob.html
    pub fn from_c_int(uint: c_int) !@This() {
        return switch (uint) {
            1 => .int,
            2 => .real,
            3 => .text,
            4 => .blob,
            5 => .null,
            else => Error.InvalidSqliteTypeValue,
        };
    }
};

pub const SqliteVal = union(enum) {
    text: []const u8,
    blob: ?*const anyopaque,
    int: i128,
    real: f64,
    null,

    pub fn free_texts(vals: []@This(), allocator: std.mem.Allocator) void {
        for (vals) |val| {
            switch (val) {
                .text => |t| allocator.free(t),
                else => continue,
            }
        }
    }

    pub fn from_stmt_col(
        stmt: ?*c.sqlite3_stmt,
        idx: c_int,
        allocator: std.mem.Allocator,
    ) !@This() {
        const ty = c.sqlite3_column_type(stmt, idx);

        return switch (ty) {
            // int
            1 => i: {
                const val = c.sqlite3_column_int(stmt, idx);
                const int: i128 = @intCast(val);
                break :i .{ .int = int };
            },
            // real
            2 => f: {
                const val = c.sqlite3_column_double(stmt, idx);
                const flt: f64 = @floatCast(val);
                break :f .{ .real = flt };
            },
            // text
            3 => t: {
                const val = c.sqlite3_column_text(stmt, idx);
                const data = try root.cstr_to_str(val, allocator);

                break :t .{ .text = data };
            },
            // blob
            4 => b: {
                const val = c.sqlite3_column_blob(stmt, idx);
                break :b .{ .blob = val };
            },
            // null
            5 => .null,
            else => Error.InvalidSqliteTypeValue,
        };
    }

    pub fn print(self: *const @This()) void {
        switch (self.*) {
            .int => |i| std.debug.print("sql-val -> {d}\n", .{i}),
            .real => |r| std.debug.print("sql-val -> {d}\n", .{r}),
            .text => |t| std.debug.print("sql-val -> {s}\n", .{t}),
            .blob => |b| std.debug.print("sql-val -> {any}\n", .{b}),
            .null => std.debug.print("sql-val -> NULL", .{}),
        }
    }
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

    pub fn text(self: *@This(), col: []const u8, val: []const u8) !void {
        // const len = val.len;
        // @compileLog(@TypeOf(val) == *const [len:0]u8);
        // if (@TypeOf(val) != *const [len:0]u8) {
        //     return Error.ValueTypeMismatch;
        // }
        // const cstr: [*c]const u8 = @ptrCast(val);
        try self.*.rows.put(col, SqliteVal{ .text = val });
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
        query.push(')');

        return .{ query, slice };
    }

    pub fn statement(self: *@This(), allocator: std.mem.Allocator) !Statement {
        var query, const bindings = try self.gen_stmt_vals(allocator);
        _ = try query.shrink_to_size(allocator);
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
    bindings: ?[]SqliteVal,
    idx: usize,
    errmsg: [*c]const u8,
    stmt: ?*c.sqlite3_stmt,

    // note that Statement deinits the String
    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) c_int {
        self.*.query.deinit(allocator);
        if (self.*.bindings) |bindings| {
            allocator.free(bindings);
        }

        return c.sqlite3_finalize(self.*.stmt);
    }

    pub fn update_bindings(
        self: *@This(),
        allocator: std.mem.Allocator,
        bindings: []SqliteVal,
    ) void {
        defer if (self.*.bindings) |b| allocator.free(b);
        self.*.bindings = bindings;
    }

    pub fn catch_error(self: *@This(), db: ?*c.sqlite3) void {
        self.*.errmsg = c.sqlite3_errmsg(db);
    }

    pub fn prepare(self: *@This(), db: ?*c.sqlite3) !void {
        std.debug.print("<{s}>\n", .{self.*.query.as_cstr()});
        if (c.SQLITE_OK != c.sqlite3_prepare_v2(
            db,
            self.*.query.as_cstr(),
            @intCast(self.*.query.len() + 1),
            &self.stmt,
            null,
        )) {
            self.catch_error(db);
            std.debug.print(">{s}<\n", .{self.*.errmsg});
            return Error.FailedToPrepareSqliteStatement;
        }
    }

    pub fn bind(self: *Statement, db: ?*c.sqlite3) !void {
        const c_idx: c_int = @intCast(self.*.idx + 1);
        const bind_op = switch (self.*.bindings.?[self.*.idx]) {
            .text => |t| t: {
                const ctext: [*c]const u8 = @ptrCast(t);
                break :t c.sqlite3_bind_text(
                    self.*.stmt,
                    c_idx,
                    ctext,
                    @intCast(std.mem.len(ctext)),
                    c.SQLITE_STATIC,
                );
            },
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
            std.debug.print(">{s}<\n", .{self.*.errmsg});
            return Error.SqliteBindFailed;
        }
        self.*.idx += 1;
    }

    pub fn bind_all(self: *Statement, db: ?*c.sqlite3) !void {
        if (self.*.bindings) |b| {
            for (0..b.len) |i| {
                _ = i;
                try self.bind(db);
            }
        }
    }

    pub fn step(self: *Statement, db: ?*c.sqlite3) !bool {
        return switch (c.sqlite3_step(self.stmt)) {
            c.SQLITE_DONE => true,
            c.SQLITE_ROW => false,
            else => {
                self.catch_error(db);
                std.debug.print(">{s}<\n", .{self.errmsg});

                return Error.FailedAtStep;
            },
        };
    }

    pub fn reset(self: *@This()) void {
        _ = c.sqlite3_reset(self.*.stmt);
    }
};
