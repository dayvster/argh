const std = @import("std");

pub fn printWrapped(text: []const u8, indent: usize) void {
    var line_col: usize = 0;
    var indent_buf: [64]u8 = undefined;
    if (indent > indent_buf.len) return;
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        indent_buf[i] = ' ';
    }
    for (text) |c| {
        if (line_col == 0 and indent > 0) std.debug.print("{s}", .{indent_buf[0..indent]});
        std.debug.print("{c}", .{c});
        line_col += 1;
        if (line_col >= 50 and c == ' ') {
            std.debug.print("\n", .{});
            line_col = 0;
        }
    }
}

pub fn resolveOptionAlias(
    name: []const u8,
    option_aliases: std.StringHashMapUnmanaged([]const u8),
    short_options: std.StringHashMapUnmanaged([]const u8),
) []const u8 {
    if (option_aliases.get(name)) |alias| return alias;
    if (short_options.get(name)) |opt| return opt;
    return name;
}

pub fn resolveFlagAlias(
    name: []const u8,
    flag_aliases: std.StringHashMapUnmanaged([]const u8),
    short_flags: std.StringHashMapUnmanaged([]const u8),
) []const u8 {
    if (flag_aliases.get(name)) |alias| return alias;
    if (short_flags.get(name)) |flag| return flag;
    return name;
}

pub fn padToColumn(buf: []u8, line_len: usize, min_col: usize) usize {
    var pad_len = line_len;
    while (pad_len < min_col and pad_len < buf.len) : (pad_len += 1) {
        buf[pad_len] = ' ';
    }
    return pad_len;
}
