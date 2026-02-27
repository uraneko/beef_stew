const std = @import("std");
const sqlite = @import("../sqlite.zig");
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
    /// select conditions, e.g., where x = y;
    conditions: std.StringHashMap([]const u8),

    pub fn init(table: []const u8, allocator: std.mem.Allocator, columns: ?[][]const u8) !@This() {
        const cols = if (columns) |cols| Cols{ .columns = cols } else .glob;
        return .{
            .table = table,
            .columns = cols,
            .conditions = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.*.conditions.deinit();
    }

    pub fn condition(self: *@This(), col: []const u8, val: []const u8) !void {
        try self.*.conditions.put(col, val);
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
            stmt.extend("' and ");
        }
        _ = try stmt.pop_index(5);
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

    pub fn select(self: *@This(), db: ?*c.sqlite3, allocator: std.mem.Allocator) !?[*c]const u8 {
        var stmt = try self.statement(allocator);
        defer _ = stmt.deinit(allocator);
        try stmt.prepare(db);

        // TODO actually handle fetched values
        // would need to make columns.columns data a hashmap to include the types of the columns being fetched
        // also probably make return type anytype and try to return different anon structs
        // NOTE only select some_text from table_name where c0 = f0 and c1 = f1...
        // currently works
        var idx: c_int = 0;
        var val: ?[*c]const u8 = null;
        while (!try stmt.step(db)) {
            val = c.sqlite3_column_text(stmt.stmt, idx);
            std.debug.print("-> >{s}<\n", .{val.?});
            idx += 1;
            // val = c.sqlite3_column_text(stmt.stmt, idx);
            // std.debug.print("-> >{s}<\n", .{val.?});
            // idx += 1;
            // const i = c.sqlite3_column_int(stmt.stmt, idx);
            // std.debug.print("-> >{d}<\n", .{i});
            // idx += 1;
        }

        return val;
    }
};
