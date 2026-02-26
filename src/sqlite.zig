const std = @import("std");
const root = @import("./root.zig");
const c = root.c;
const err = root.Error;

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

pub fn execute(
    db: ?*c.sqlite3,
    allocator: std.mem.Allocator,
    operation: anytype,
) !void {
    const act = std.meta.stringToEnum(Action, operation.action()) orelse unreachable;
    switch (act) {
        .create => try operation.create(db, allocator),
    }
}

pub const Action = enum {
    create,
};

pub const CreateTable = struct {
    name: []const u8,
    columns: []Column,

    pub fn new(name: []const u8, columns: []Column) @This() {
        return CreateTable{
            .name = name,
            .columns = columns,
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.columns);
    }

    pub fn action(self: @This()) []const u8 {
        _ = &self;

        return "create";
    }

    // WARN if you use this
    // you are responsible for freeing once done with the value
    pub fn statement(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        var stt: []u8 = try allocator.alloc(u8, 4096);
        var idx: usize = 0;
        extend_bytes(&stt, "create table if not exists ", &idx);
        extend_bytes(&stt, self.name, &idx);
        extend_bytes(&stt, " (", &idx);

        for (self.columns) |column| {
            try column.dump(&stt, &idx);
            extend_bytes(&stt, ", ", &idx);
        }
        idx -= 2;
        extend_bytes(&stt, ") strict;", &idx);

        if (stt.len > idx) {
            stt = try allocator.realloc(stt, idx);
        }

        return stt;
    }

    pub fn create(self: @This(), db: ?*c.sqlite3, allocator: std.mem.Allocator) !void {
        var errmsg: [*c]u8 = undefined;
        const stt = try self.statement(allocator);
        defer allocator.free(stt);

        const c_stt: [*c]const u8 = @ptrCast(stt);
        std.debug.print("\n\n>>>{s}<<<\n\n", .{c_stt});
        if (c.SQLITE_OK != c.sqlite3_exec(db, c_stt, null, null, &errmsg)) {
            defer c.sqlite3_free(errmsg);
            std.debug.print("\n*** {s}\n", .{errmsg});

            return Error.SqliteExecFailed;
        }
    }
};

const Error = error{
    TableNameTypeCantBeUndefined,
    PKConstraintCantCoexistWithUnique,
    SqliteExecFailed,
};

pub const Column = struct {
    name_: []const u8,
    type_: SqliteType,
    pk_: bool,
    unique_: bool,
    not_null_: bool,

    pub fn new(name_: []const u8, type_: []const u8) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        return Column{
            .name_ = name_,
            .type_ = type_from_str,
            .pk_ = false,
            .unique_ = false,
            .not_null_ = false,
        };
    }

    pub fn new_pk(name_: []const u8, type_: []const u8) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        return Column{
            .name_ = name_,
            .type_ = type_from_str,
            .pk_ = true,
            .unique_ = false,
            .not_null_ = false,
        };
    }

    pub fn with_flags(name_: []const u8, type_: []const u8, u: bool, nn: bool) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        return Column{
            .name_ = name_,
            .type_ = type_from_str,
            .pk_ = false,
            .unique_ = u,
            .not_null_ = nn,
        };
    }

    pub fn name(self: Column, name_: []const u8) Column {
        @compileLog(@TypeOf(self));
        self.name_ = name_;

        return self;
    }

    pub fn ty(self: Column, type_: []const u8) Column {
        const type_from_str = std.meta.stringToEnum(SqliteType, type_) orelse unreachable;
        self.type_ = type_from_str;

        return self;
    }

    pub fn pk(self: Column, pk_: bool) Column {
        self.pk_ = pk_;

        return self;
    }

    pub fn unique(self: Column, unique_: bool) Column {
        self.unique_ = unique_;

        return self;
    }

    pub fn not_null(self: Column, nn: bool) Column {
        self.not_null_ = nn;

        return self;
    }

    fn dump(self: Column, stt: *[]u8, idx: *usize) !void {
        // TODO self.type_ check
        if (std.mem.eql(u8, self.name_, undefined)) {
            return Error.TableNameTypeCantBeUndefined;
        } else if (self.pk_ and (self.unique_ or self.not_null_)) {
            return Error.PKConstraintCantCoexistWithUnique;
        }

        extend_bytes(stt, self.name_, idx);
        push_byte(stt, ' ', idx);
        extend_bytes(stt, self.type_.as_str(), idx);

        if (self.pk_) {
            extend_bytes(stt, " primary key", idx);
        } else {
            if (self.unique_) {
                extend_bytes(stt, " unique", idx);
            }

            if (self.not_null_) {
                extend_bytes(stt, " not null", idx);
            }
        }
    }
};

fn push_byte(self: *[]u8, byte: u8, idx: *usize) void {
    self.*[idx.*] = byte;
    idx.* += 1;
}

fn extend_bytes(self: *[]u8, bytes: []const u8, idx: *usize) void {
    const len = bytes.len;
    for (idx.*..len + idx.*, 0..len) |sidx, bidx| {
        self.*[sidx] = bytes[bidx];
    }
    idx.* += len;
}

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
