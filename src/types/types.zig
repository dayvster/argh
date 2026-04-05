const std = @import("std");

pub const ParseError = error{
    InvalidType,
    InvalidValue,
    InvalidFlagName,
    InvalidOption,
    InvalidFlag,
    OutOfRange,
    AliasConflict,
    InvalidAliasFormat,
    OutOfMemory,
};

pub const OptionType = enum { string, int, float, bool };

pub const HelpStyle = enum { flat, simple_grouped, complex_grouped };

pub const FlagInfo = struct {
    help: []const u8,
    required: bool = false,
    group: ?[]const u8 = null,
    hidden: bool = false,
    deprecated: bool = false,
    count: usize = 0,
};

pub const OptionInfo = struct {
    help: []const u8,
    value: []const u8,
    default: []const u8,
    required: bool = false,
    typ: OptionType = .string,
    group: ?[]const u8 = null,
    hidden: bool = false,
    deprecated: bool = false,
    min_int: ?i64 = null,
    max_int: ?i64 = null,
    min_float: ?f64 = null,
    max_float: ?f64 = null,
};

pub const PositionalInfo = struct {
    name: []const u8,
    help: []const u8,
    value: ?[]const u8 = null,
    required: bool = false,
    default: ?[]const u8 = null,
    typ: OptionType = .string,
    hidden: bool = false,
    deprecated: bool = false,
    min_count: usize = 1,
    max_count: usize = 1,
};

pub const MutexGroup = struct {
    members: std.ArrayListUnmanaged([]const u8),
};
