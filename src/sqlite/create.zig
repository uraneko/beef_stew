const std = @import("std");
const sqlite = @import("../sqlite.zig");
const c = @import("../root.zig").c;
const String = @import("../root.zig").String;
const Error = sqlite.Error;
const SqliteType = sqlite.SqliteType;
const extend = sqlite.extend_bytes;
const push = sqlite.push_byte;

pub const CreateTable = struct {
    name: []const u8,
    columns_: []Column,
    idx: usize,

    pub fn init(name: []const u8, allocator: std.mem.Allocator, size: usize) !@This() {
        return CreateTable{
            .name = name,
            .idx = 0,
            .columns_ = try allocator.alloc(Column, size),
        };
    }

    pub fn deinit(self: *CreateTable, allocator: std.mem.Allocator) void {
        allocator.free(self.*.columns_);
    }

    pub fn column(self: *@This(), params: struct {
        []const u8,
        []const u8,
        bool,
        bool,
        bool,
    }) !void {
        self.*.columns_[self.*.idx] = try Column.from_params(params);
        self.*.idx += 1;
    }

    pub fn columns(self: *CreateTable, arr: []struct {
        []const u8,
        []const u8,
        bool,
        bool,
        bool,
    }) !void {
        for (arr) |params| {
            try self.column(params);
        }
    }

    pub fn len(self: *const CreateTable) usize {
        return self.*.columns_.len;
    }

    // WARN if you use this
    // you are responsible for freeing the return value once done with it
    pub fn statement(self: @This(), allocator: std.mem.Allocator) !String {
        var stmt = try String.init(allocator, 4096);
        stmt.extend("create table if not exists ");
        stmt.extend(self.name);
        stmt.extend(" (");

        for (self.columns_) |column_| {
            try column_.dump(&stmt);
            stmt.extend(", ");
        }
        _ = try stmt.pop_index(2);
        stmt.extend(") strict;");

        _ = try stmt.shrink_to_size(allocator);

        return stmt;
    }

    pub fn create(self: @This(), db: ?*c.sqlite3, allocator: std.mem.Allocator) !void {
        var errmsg: [*c]u8 = undefined;
        var stmt = try self.statement(allocator);
        defer stmt.deinit(allocator);

        // const c_stt: [*c]const u8 = @ptrCast(stt);
        const c_stmt = stmt.as_cstr();
        if (c.SQLITE_OK != c.sqlite3_exec(db, c_stmt, null, null, &errmsg)) {
            std.debug.print("sqlite table create execution error: {s}\n", .{errmsg});
            defer c.sqlite3_free(errmsg);

            return Error.SqliteExecFailed;
        }
    }
};

pub const Column = struct {
    name: []const u8,
    type_: SqliteType,
    pk: bool,
    unique: bool,
    not_null: bool,

    pub fn new(name_: []const u8, type_: []const u8) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        return Column{
            .name = name_,
            .type_ = type_from_str,
            .pk = false,
            .unique = false,
            .not_null = false,
        };
    }

    pub fn new_pk(name_: []const u8, type_: []const u8) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        return Column{
            .name = name_,
            .type_ = type_from_str,
            .pk = true,
            .unique = false,
            .not_null = false,
        };
    }

    pub fn with_flags(name: []const u8, type_: []const u8, u: bool, nn: bool) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        return Column{
            .name = name,
            .type_ = type_from_str,
            .pk = false,
            .unique = u,
            .not_null = nn,
        };
    }

    pub fn from_params(params: struct { []const u8, []const u8, bool, bool, bool }) !@This() {
        const name, const type_, const pk, const unique, const not_null = params;
        if (pk and (unique or not_null)) {
            return Error.PKConstraintCantCoexistWithUnique;
        }

        if (pk) {
            return Column.new_pk(name, type_);
        } else if (unique or not_null) {
            return Column.with_flags(
                name,
                type_,
                unique,
                not_null,
            );
        } else {
            return Column.new(name, type_);
        }
    }

    fn dump(self: Column, stmt: *String) !void {
        // TODO self.type_ check
        if (std.mem.eql(u8, self.name, undefined)) {
            return Error.TableNameTypeCantBeUndefined;
        } else if (self.pk and (self.unique or self.not_null)) {
            return Error.PKConstraintCantCoexistWithUnique;
        }

        stmt.extend(self.name);
        stmt.push(' ');
        stmt.extend(self.type_.as_str());

        if (self.pk) {
            stmt.extend(" primary key");
        } else {
            if (self.unique) {
                stmt.extend(" unique");
            }

            if (self.not_null) {
                stmt.extend(" not null");
            }
        }
    }
};
