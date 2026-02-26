const std = @import("std");
const sqlite = @import("../sqlite.zig");
const c = @import("../root.zig").c;
const Error = sqlite.Error;
const extend = sqlite.extend_bytes;

pub const QueryTable = struct {
    table: []const u8,
    columns: [][]const u8,
    conditions: std.AutoHashMap([]const u8, []const u8),
};
