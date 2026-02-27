const std = @import("std");
const sqlite = @import("../sqlite.zig");
const c = @import("../root.zig").c;
const String = @import("../root.zig").String;
const Error = sqlite.Error;
const extend = sqlite.extend_bytes;
const Stmt = sqlite.Statement;
const StmtConstr = sqlite.StatementConstructor;

pub const InsertIntoTable = struct {
    table: []const u8,
    rows_: std.AutoHashMap([]const u8, []const u8),

    pub fn new(table: []const u8, allocator: std.mem.Allocator) @This() {
        return @This(){
            .table = table,
            .rows_ = .init(allocator),
        };
    }

    pub fn deinit(self: @This()) void {
        self.rows_.deinit();
    }

    pub fn rows(self: *@This(), rows_: [].{ []const u8, []const u8 }) !void {
        for (rows_) |row_| {
            try self.row(row_[0], row_[1]);
        }
    }

    pub fn row(self: *@This(), key: []const u8, val: []const u8) !void {
        try self.*.rows_.put(key, val);
    }

    pub fn dump_rows(self: *const @This(), stmt: *String) !void {
        var keyiter = self.*.rows_.keyIterator();
        while (try keyiter.next()) |key| {
            stmt.extend(key);
            stmt.extend(", ");
        }
        _ = stmt.pop_index(2);
        stmt.extend(") (");

        // TODO need to use sqlite_prepare + sqlite_bind + sqlite_step + sqlite_finalize
        var valiter = self.*.rows_.valIterator();
        while (try valiter.next()) |val| {
            stmt.extend(val);
            stmt.extend(", ");
        }
        _ = stmt.pop_index(2);
    }

    pub fn statement(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        var stmt = try String.init(allocator, 4096);
        stmt.extend("insert into ");
        stmt.extend(self.*.table);
        stmt.extend(" (");

        return stmt;
    }

    pub fn insert(self: @This(), db: ?*c.sqlite3, allocator: std.mem.Allocator) !void {
        var errmsg: [*c]u8 = undefined;
        var stmt = try self.statement(allocator);
        defer stmt.deinit(allocator);

        const c_stmt = stmt.as_cstr();
        if (c.SQLITE_OK != c.sqlite3.exec(db, c_stmt, null, null, &errmsg)) {
            std.debug.print("sqlite table insert execution error: {s}", .{errmsg});
            defer c.sqlite3_free(errmsg);

            return Error.SqliteExecFailed;
        }
    }
};
