const std = @import("std");
const sqlite = @import("../sqlite.zig");
const SqliteType = sqlite.SqliteType;
const SqliteVal = sqlite.SqliteVal;
const Statement = sqlite.Statement;
const c = @import("../root.zig").c;
const Error = sqlite.Error;
const String = @import("../root.zig").String;
const extend = sqlite.extend_bytes;

const Cols = union(enum) {
    columns: [][]const u8,
    glob,
};

// select x,y,z from tname where c = a and b = d;
pub const Select = struct {
    /// table name to select from
    table: []const u8,
    /// columns to keep
    columns: Cols,
    /// the operator to use for the conditions if any
    operator_: []const u8,
    /// select conditions, e.g., where x = y;
    conditions: std.StringHashMap([]const u8),

    pub fn init(table: []const u8, allocator: std.mem.Allocator, columns: ?[][]const u8) !@This() {
        const cols = if (columns) |cols| Cols{ .columns = cols } else .glob;
        return .{
            .table = table,
            .columns = cols,
            .conditions = .init(allocator),
            .operator_ = "or",
        };
    }

    pub fn deinit(self: *@This()) void {
        self.*.conditions.deinit();
    }

    // this should be a list, array...
    // since a hashmap doesnt allow for duplicate keys
    pub fn condition(self: *@This(), col: []const u8, val: []const u8) !void {
        try self.*.conditions.put(col, val);
    }

    pub fn operator(self: *@This(), operator_: []const u8) void {
        self.operator_ = operator_;
    }

    pub fn query(self: *@This(), allocator: std.mem.Allocator) !String {
        var stmt = try String.init(allocator, 512);
        stmt.extend("select ");
        switch (self.*.columns) {
            .glob => {
                stmt.extend("* from ");
            },
            .columns => |cols| {
                for (0..cols.len) |idx| {
                    stmt.extend(cols[idx]);
                    if (idx == cols.len - 1) {
                        stmt.extend(" from ");
                    } else {
                        stmt.extend(", ");
                    }
                }
            },
        }
        stmt.extend(self.*.table);

        if (self.*.conditions.count() == 0) {
            // stmt.push(';');
            _ = try stmt.shrink_to_size(allocator);
            return stmt;
        }
        stmt.extend(" where ");
        var iter = self.*.conditions.iterator();
        while (iter.next()) |entry| {
            stmt.ptr_extend(entry.key_ptr);
            stmt.extend(" = '");
            stmt.ptr_extend(entry.value_ptr);
            stmt.extend("' ");
            stmt.extend(self.*.operator_);
            stmt.push(' ');
        }
        _ = try stmt.pop_index(2 + self.*.operator_.len);
        // stmt.push(';');
        _ = try stmt.shrink_to_size(allocator);

        return stmt;
    }

    pub fn statement(self: *Select, allocator: std.mem.Allocator) !Statement {
        return .{
            .query = try self.query(allocator),
            .idx = 0,
            .bindings = null,
            .errmsg = undefined,
            .stmt = undefined,
        };
    }

    // sqlite3 selection works like so:
    // 1= prepare statement
    // 2= make a step <- this gives us a single row of all the requested columns values
    // 3= get the row values using as many qlite3_column_<type> function
    // calls as needed (watch out for the order of values)
    // 4= repeat 2..=3 until SQLITE_DONE is returned
    pub fn select(
        self: *@This(),
        db: ?*c.sqlite3,
        allocator: std.mem.Allocator,
        // estimated number of result rows
        estimate: usize,
        rlen: usize,
    ) ![]SqliteVal {
        var stmt = try self.statement(allocator);
        defer _ = stmt.deinit(allocator);
        try stmt.prepare(db);

        var slice = try allocator.alloc(SqliteVal, estimate * rlen);
        // every step taken fetchs a row
        var idx: usize = 0;
        // WARN sqlite fetched text, blob data is invalidated when step,
        // reset or finalize are called
        while (!try stmt.step(db)) {
            for (0..rlen) |pos| {
                const rpos: c_int = @intCast(pos);
                slice[idx + pos] = try SqliteVal.from_stmt_col(stmt.stmt, rpos, allocator);
            }
            idx += rlen;
        }

        if (slice.len > idx) {
            slice = try allocator.realloc(slice, idx);
        }

        // for (slice) |s| {
        //     s.print();
        // }

        return slice;
    }
};
