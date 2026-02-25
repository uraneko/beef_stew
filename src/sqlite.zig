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

pub fn execute(db: ?*c.sqlite3, allocator: std.mem.Allocator, operation: type) !void {
    switch (operation) {
        CreateTable => try CreateTable.create(db, allocator),
        _ => unreachable,
    }
}

pub fn Operation(comptime action: []const u8) type {
    const act = std.meta.StringToEnum(Action, action);
    switch (act) {
        .create => CreateTable,
        _ => unreachable,
    }
}

pub const Action = enum {
    create,
};

pub const CreateTable = struct {
    name: []const u8,
    columns: []Column,

    pub fn new(name: []const u8, columns: []Column) @This() {
        return @This(){
            .name = name,
            .columns = columns,
        };
    }

    // WARN if you use this
    // you are responsible for freeing once done with the value
    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        var query = allocator.alloc(u8, 4096);
        var idx = 0;
        extend_bytes(&query, "create table if not exists ", &idx);
        extend_bytes(&query, self.name, &idx);
        extend_bytes(&query, " (", &idx);

        for (self.columns) |column| {
            try column.build(query, idx);
        }
        extend_bytes(&query, ") strict;", &idx);

        if (query.length > idx) {
            query = try allocator.realloc(query, idx + 1);
        }
    }

    pub fn create(self: @This(), db: ?*c.sqlite3, allocator: std.mem.Allocator) !void {
        var errmsg: [*c]u8 = undefined;
        const query = try self.serialize(allocator);
        defer allocator.free(query);

        if (c.SQLITE_OK != c.sqlite3_exec(db, query, null, null, &errmsg)) {
            defer c.sqlite3_free(errmsg);

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

    pub fn builder() Column {
        return Column{
            .name_ = undefined,
            .type_ = undefined,
            .pk_ = false,
            .unique_ = false,
            .not_null_ = false,
        };
    }

    pub fn name(self: Column, name_: []const u8) @This() {
        self.name_ = name_;

        return self;
    }

    pub fn ty(self: Column, type_: SqliteType) Column {
        self.type_ = type_;

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

    fn build(self: Column, query: *[]u8, idx: *usize) !void {
        if (self.name_ == undefined or self.ty_ == undefined) {
            return Error.TableNameTypeCantBeUndefined;
        } else if (self.pk_ and (self.unique_ or self.not_null_)) {
            return Error.PKConstraintCantCoexistWithUnique;
        }

        extend_bytes(&query, self.name_, &idx);
        push_byte(&query, ' ', &idx);
        extend_bytes(&query, self.type_.as_str(), &idx);

        if (self.pk_) {
            extend_bytes(&query, " primary key", &idx);
        } else {
            if (self.unique_) {
                extend_bytes(&query, " unique", &idx);
            }

            if (self.not_null_) {
                extend_bytes(&query, " not null", &idx);
            }
        }

        return query;
    }
};

fn push_byte(self: *[]u8, byte: u8, idx: *usize) void {
    self[idx] = byte;
    idx += 1;
}

fn extend_bytes(
    self: *[]u8,
    bytes: []const u8,
    idx: *usize,
) void {
    const len = bytes.length;
    std.mem.copyForwards(u8, self[idx..], bytes);
    idx += len;
}

pub const SqliteType = enum {
    Text,
    Blob,
    Int,
    Real,
    Null,

    pub fn as_str(self: *const @This()) []const u8 {
        switch (self) {
            .Text => "text",
            .Blob => "blob",
            .Int => "integer",
            .Real => "real",
            .Null => "null",
        }
    }
};
