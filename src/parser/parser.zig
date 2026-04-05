const std = @import("std");
const types = @import("../types/types.zig");
const utils = @import("../utils/utils.zig");

pub const ParseError = types.ParseError;
pub const OptionType = types.OptionType;
pub const FlagInfo = types.FlagInfo;
pub const OptionInfo = types.OptionInfo;
pub const PositionalInfo = types.PositionalInfo;
pub const MutexGroup = types.MutexGroup;

fn isValidAliasFormat(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "--")) return true;
    if (std.mem.startsWith(u8, name, "-") and name.len == 2) return true;
    return false;
}

pub const Parser = struct {
    allocator: std.mem.Allocator,
    args: []const [:0]const u8,
    program_name: ?[]const u8 = null,
    flags: std.StringHashMapUnmanaged(*FlagInfo),
    flag_counts: std.AutoHashMapUnmanaged(*FlagInfo, usize),
    options: std.StringHashMapUnmanaged(OptionInfo),
    short_options: std.StringHashMapUnmanaged([]const u8),
    short_flags: std.StringHashMapUnmanaged([]const u8),
    option_aliases: std.StringHashMapUnmanaged([]const u8),
    flag_aliases: std.StringHashMapUnmanaged([]const u8),
    positionals: std.ArrayListUnmanaged(PositionalInfo),
    errors: std.ArrayListUnmanaged([]const u8),
    deprecation_warnings: std.ArrayListUnmanaged([]const u8),
    mutex_groups: std.StringHashMapUnmanaged(MutexGroup),
    subcommands: std.StringHashMapUnmanaged(*Parser),

    pub fn init(allocator: std.mem.Allocator, args: []const [:0]const u8) Parser {
        return Parser{
            .allocator = allocator,
            .args = args,
            .flags = .{},
            .flag_counts = .{},
            .options = .{},
            .short_options = .{},
            .short_flags = .{},
            .option_aliases = .{},
            .flag_aliases = .{},
            .positionals = .{},
            .errors = .{},
            .deprecation_warnings = .{},
            .mutex_groups = .{},
            .subcommands = .{},
        };
    }

    pub fn setProgramName(self: *Parser, name: []const u8) void {
        if (self.program_name) |old| {
            self.allocator.free(old);
        }
        const copy = self.allocator.alloc(u8, name.len) catch {
            self.program_name = name;
            return;
        };
        std.mem.copyForwards(u8, copy, name);
        self.program_name = copy;
    }

    pub fn getSubcommand(self: *Parser) ?[]const u8 {
        if (self.args.len > 0) {
            const first = self.args[0];
            if (self.subcommands.contains(first)) {
                return first;
            }
        }
        return null;
    }

    fn appendError(self: *Parser, msg: []const u8, arg: ?[]const u8) !void {
        const full = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ msg, arg orelse "" });
        try self.errors.append(self.allocator, full);
    }

    pub fn getSubcommandParser(self: *Parser) ?*Parser {
        if (self.args.len > 0) {
            const first = self.args[0];
            if (self.subcommands.get(first)) |subparser| {
                return subparser;
            }
        }
        return null;
    }

    pub fn parseWithSubcommand(self: *Parser) !?*Parser {
        if (self.getSubcommandParser()) |subparser| {
            subparser.args = self.args[1..];
            try subparser.parse();
            return subparser;
        } else {
            try self.parse();
            return null;
        }
    }

    pub fn getOptionBool(self: *Parser, name: []const u8) !?bool {
        const resolved = utils.resolveOptionAlias(name, self.option_aliases, self.short_options);
        if (self.options.get(resolved)) |opt| {
            if (opt.typ != .bool) return error.InvalidType;
            const val = std.mem.trim(u8, opt.value, " \t\n\r");
            if (std.ascii.eqlIgnoreCase(val, "true") or std.ascii.eqlIgnoreCase(val, "yes") or std.ascii.eqlIgnoreCase(val, "1"))
                return true;
            if (std.ascii.eqlIgnoreCase(val, "false") or std.ascii.eqlIgnoreCase(val, "no") or std.ascii.eqlIgnoreCase(val, "0"))
                return false;
            return error.InvalidValue;
        }
        return null;
    }

    pub fn addFlag(self: *Parser, short: []const u8, long: []const u8, help: []const u8) !void {
        try self.addFlagWithOptions(short, long, help, false, false, null);
    }

    pub fn addHiddenFlag(self: *Parser, short: []const u8, long: []const u8, help: []const u8) !void {
        try self.addFlagWithOptions(short, long, help, true, false, null);
    }

    pub fn addRequiredFlag(self: *Parser, short: []const u8, long: []const u8, help: []const u8) !void {
        try self.addFlagWithOptions(short, long, help, false, true, null);
    }

    fn addFlagWithOptions(self: *Parser, short: []const u8, long: []const u8, help: []const u8, hidden: bool, required: bool, group: ?[]const u8) !void {
        if (short.len == 0) return error.InvalidFlagName;
        const has_long = long.len > 0;
        const flag_ptr = try self.allocator.create(FlagInfo);
        flag_ptr.* = FlagInfo{ .help = help, .hidden = hidden, .required = required, .group = group };
        try self.flags.put(self.allocator, short, flag_ptr);
        if (has_long) {
            try self.flags.put(self.allocator, long, flag_ptr);
            try self.short_flags.put(self.allocator, short, long);
            try self.short_flags.put(self.allocator, long, short);
        }
        try self.flag_counts.put(self.allocator, flag_ptr, 0);
    }

    pub fn addPositional(self: *Parser, name: []const u8, help: []const u8, required: bool, default: ?[]const u8) !void {
        try self.positionals.append(self.allocator, PositionalInfo{
            .name = name,
            .help = help,
            .required = required,
            .default = default,
            .min_count = 1,
            .max_count = 1,
        });
    }

    pub fn addPositionalWithCount(self: *Parser, name: []const u8, help: []const u8, min_count: usize, max_count: usize) !void {
        try self.addPositionalWithCountAndHidden(name, help, min_count, max_count, false);
    }

    pub fn addHiddenPositionalWithCount(self: *Parser, name: []const u8, help: []const u8, min_count: usize, max_count: usize) !void {
        try self.addPositionalWithCountAndHidden(name, help, min_count, max_count, true);
    }

    fn addPositionalWithCountAndHidden(self: *Parser, name: []const u8, help: []const u8, min_count: usize, max_count: usize, hidden: bool) !void {
        try self.positionals.append(self.allocator, PositionalInfo{
            .name = name,
            .help = help,
            .required = min_count > 0,
            .default = null,
            .hidden = hidden,
            .min_count = min_count,
            .max_count = max_count,
        });
    }

    pub fn addMutexGroup(self: *Parser, group_name: []const u8, members: []const []const u8) !void {
        var group = MutexGroup{ .members = .{} };
        try group.members.appendSlice(self.allocator, members);
        try self.mutex_groups.put(self.allocator, group_name, group);
    }

    pub fn addOptionAlias(self: *Parser, alias: []const u8, canonical: []const u8) ParseError!void {
        if (self.options.get(canonical) == null) return error.InvalidOption;
        if (!isValidAliasFormat(alias)) return error.InvalidAliasFormat;
        if (self.options.contains(alias) or self.flags.contains(alias) or
            self.short_options.contains(alias) or self.short_flags.contains(alias) or
            self.option_aliases.contains(alias) or self.flag_aliases.contains(alias))
        {
            return error.AliasConflict;
        }
        try self.option_aliases.put(self.allocator, alias, canonical);
    }

    pub fn addFlagAlias(self: *Parser, alias: []const u8, canonical: []const u8) ParseError!void {
        if (self.flags.get(canonical) == null) return error.InvalidFlag;
        if (!isValidAliasFormat(alias)) return error.InvalidAliasFormat;
        if (self.options.contains(alias) or self.flags.contains(alias) or
            self.short_options.contains(alias) or self.short_flags.contains(alias) or
            self.option_aliases.contains(alias) or self.flag_aliases.contains(alias))
        {
            return error.AliasConflict;
        }
        try self.flag_aliases.put(self.allocator, alias, canonical);
    }

    pub fn addOption(self: *Parser, long: []const u8, short: ?[]const u8, default: []const u8, help: []const u8) !void {
        try self.addOptionWithOptions(long, short, default, help, false, false, null);
    }

    pub fn addHiddenOption(self: *Parser, long: []const u8, short: ?[]const u8, default: []const u8, help: []const u8) !void {
        try self.addOptionWithOptions(long, short, default, help, true, false, null);
    }

    pub fn addRequiredOption(self: *Parser, long: []const u8, short: ?[]const u8, help: []const u8) !void {
        try self.addOptionWithOptions(long, short, "", help, false, true, null);
    }

    fn addOptionWithOptions(self: *Parser, long: []const u8, short: ?[]const u8, default: []const u8, help: []const u8, hidden: bool, required: bool, group: ?[]const u8) !void {
        try self.options.put(self.allocator, long, OptionInfo{ .help = help, .value = default, .default = default, .hidden = hidden, .required = required, .group = group });
        if (short) |s| {
            try self.short_options.put(self.allocator, s, long);
        }
    }

    pub fn addIntOption(self: *Parser, long: []const u8, short: ?[]const u8, default: i64, help: []const u8, min: ?i64, max: ?i64) !void {
        try self.addIntOptionWithOptions(long, short, default, help, min, max, false, false, null);
    }

    pub fn addHiddenIntOption(self: *Parser, long: []const u8, short: ?[]const u8, default: i64, help: []const u8, min: ?i64, max: ?i64) !void {
        try self.addIntOptionWithOptions(long, short, default, help, min, max, true, false, null);
    }

    fn addIntOptionWithOptions(self: *Parser, long: []const u8, short: ?[]const u8, default: i64, help: []const u8, min: ?i64, max: ?i64, hidden: bool, required: bool, group: ?[]const u8) !void {
        const def_str = try std.fmt.allocPrint(self.allocator, "{}", .{default});
        try self.options.put(self.allocator, long, OptionInfo{
            .help = help,
            .value = def_str,
            .default = def_str,
            .typ = .int,
            .min_int = min,
            .max_int = max,
            .hidden = hidden,
            .required = required,
            .group = group,
        });
        if (short) |s| {
            try self.short_options.put(self.allocator, s, long);
        }
    }

    pub fn addFloatOption(self: *Parser, long: []const u8, short: ?[]const u8, default: f64, help: []const u8, min: ?f64, max: ?f64) !void {
        try self.addFloatOptionWithOptions(long, short, default, help, min, max, false, false, null);
    }

    pub fn addHiddenFloatOption(self: *Parser, long: []const u8, short: ?[]const u8, default: f64, help: []const u8, min: ?f64, max: ?f64) !void {
        try self.addFloatOptionWithOptions(long, short, default, help, min, max, true, false, null);
    }

    fn addFloatOptionWithOptions(self: *Parser, long: []const u8, short: ?[]const u8, default: f64, help: []const u8, min: ?f64, max: ?f64, hidden: bool, required: bool, group: ?[]const u8) !void {
        const def_str = try std.fmt.allocPrint(self.allocator, "{}", .{default});
        try self.options.put(self.allocator, long, OptionInfo{
            .help = help,
            .value = def_str,
            .default = def_str,
            .typ = .float,
            .min_float = min,
            .max_float = max,
            .hidden = hidden,
            .required = required,
            .group = group,
        });
        if (short) |s| {
            try self.short_options.put(self.allocator, s, long);
        }
    }

    pub fn getOptionInt(self: *Parser, name: []const u8) !?i64 {
        const resolved = utils.resolveOptionAlias(name, self.option_aliases, self.short_options);
        if (self.options.get(resolved)) |opt| {
            if (opt.typ != .int) return error.InvalidType;
            const val = try std.fmt.parseInt(i64, opt.value, 10);
            if (opt.min_int) |min| if (val < min) return error.OutOfRange;
            if (opt.max_int) |max| if (val > max) return error.OutOfRange;
            return val;
        }
        return null;
    }

    pub fn getOptionFloat(self: *Parser, name: []const u8) !?f64 {
        const resolved = utils.resolveOptionAlias(name, self.option_aliases, self.short_options);
        if (self.options.get(resolved)) |opt| {
            if (opt.typ != .float) return error.InvalidType;
            const val = try std.fmt.parseFloat(f64, opt.value);
            if (opt.min_float) |min| if (val < min) return error.OutOfRange;
            if (opt.max_float) |max| if (val > max) return error.OutOfRange;
            return val;
        }
        return null;
    }

    pub fn parse(self: *Parser) !void {
        var i: usize = 0;
        var pos_idx: usize = 0;
        var seen: std.StringHashMapUnmanaged(bool) = .{};
        defer seen.deinit(self.allocator);
        var positional_counts: []usize = try self.allocator.alloc(usize, self.positionals.items.len);
        defer self.allocator.free(positional_counts);
        for (positional_counts) |*c| c.* = 0;
        var fcit = self.flag_counts.iterator();
        while (fcit.next()) |entry| {
            entry.value_ptr.* = 0;
            entry.key_ptr.*.count = 0;
        }
        while (i < self.args.len) : (i += 1) {
            const arg = self.args[i];
            if (std.mem.startsWith(u8, arg, "--")) {
                var resolved: []const u8 = arg;
                if (self.flag_aliases.get(arg)) |alias| {
                    resolved = alias;
                } else if (self.option_aliases.get(arg)) |alias| {
                    resolved = alias;
                }
                if (self.flags.getPtr(resolved)) |flag_ptr_ptr| {
                    const flag = flag_ptr_ptr.*;
                    var canonical_flag = flag;
                    if (self.short_flags.get(resolved)) |short| {
                        if (self.flags.getPtr(short)) |short_flag_ptr_ptr| {
                            const short_flag = short_flag_ptr_ptr.*;
                            if (@intFromPtr(short_flag) < @intFromPtr(canonical_flag)) {
                                canonical_flag = short_flag;
                            }
                        }
                    }
                    if (self.flag_counts.getPtr(canonical_flag)) |count_ptr| {
                        count_ptr.* += 1;
                        canonical_flag.count += 1;
                    }
                    try seen.put(self.allocator, resolved, true);
                    if (self.short_flags.get(resolved)) |short| {
                        try seen.put(self.allocator, short, true);
                    }
                } else if (self.options.getPtr(resolved)) |opt| {
                    if (i + 1 < self.args.len) {
                        if (opt.value.ptr != opt.default.ptr) {
                            self.allocator.free(opt.value);
                        }
                        const val = self.args[i + 1];
                        const val_copy = try self.allocator.alloc(u8, val.len);
                        std.mem.copyForwards(u8, val_copy, val);
                        opt.value = val_copy;
                        i += 1;
                        try seen.put(self.allocator, resolved, true);
                    } else {
                        try self.appendError("Missing value for option: ", arg);
                    }
                } else {
                    try self.appendError("Unknown argument: ", arg);
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
                var resolved: []const u8 = arg;
                if (self.flag_aliases.get(arg)) |alias| {
                    resolved = alias;
                } else if (self.short_options.get(arg)) |opt| {
                    resolved = opt;
                } else if (self.option_aliases.get(arg)) |alias| {
                    resolved = alias;
                }
                if (self.flags.getPtr(resolved)) |flag_ptr_ptr| {
                    const flag = flag_ptr_ptr.*;
                    var canonical_flag = flag;
                    if (self.short_flags.get(resolved)) |long| {
                        if (self.flags.getPtr(long)) |long_flag_ptr_ptr| {
                            const long_flag = long_flag_ptr_ptr.*;
                            if (@intFromPtr(long_flag) < @intFromPtr(canonical_flag)) {
                                canonical_flag = long_flag;
                            }
                        }
                    }
                    if (self.flag_counts.getPtr(canonical_flag)) |count_ptr| {
                        count_ptr.* += 1;
                        canonical_flag.count += 1;
                    }
                    try seen.put(self.allocator, resolved, true);
                    if (self.short_flags.get(resolved)) |long| {
                        try seen.put(self.allocator, long, true);
                    }
                } else if (self.options.getPtr(resolved)) |opt| {
                    if (i + 1 < self.args.len) {
                        if (opt.value.ptr != opt.default.ptr) {
                            self.allocator.free(opt.value);
                        }
                        const val = self.args[i + 1];
                        const val_copy = try self.allocator.alloc(u8, val.len);
                        std.mem.copyForwards(u8, val_copy, val);
                        opt.value = val_copy;
                        i += 1;
                        try seen.put(self.allocator, resolved, true);
                    } else {
                        try self.appendError("Missing value for option: ", arg);
                    }
                } else {
                    try self.appendError("Unknown short argument: ", arg);
                }
            } else {
                if (pos_idx < self.positionals.items.len) {
                    positional_counts[pos_idx] += 1;
                    if (self.positionals.items[pos_idx].value) |old| {
                        const new_val = try self.allocator.alloc(u8, old.len + 1 + arg.len);
                        std.mem.copyForwards(u8, new_val[0..old.len], old);
                        new_val[old.len] = ' ';
                        std.mem.copyForwards(u8, new_val[old.len + 1 ..], arg);
                        self.allocator.free(old);
                        self.positionals.items[pos_idx].value = new_val;
                    } else {
                        const val_copy = try self.allocator.alloc(u8, arg.len);
                        std.mem.copyForwards(u8, val_copy, arg);
                        self.positionals.items[pos_idx].value = val_copy;
                    }
                    if (positional_counts[pos_idx] >= self.positionals.items[pos_idx].max_count) {
                        pos_idx += 1;
                    }
                } else {
                    try self.appendError("Unexpected positional argument: ", arg);
                }
            }
        }
        var checked_flags = std.AutoHashMapUnmanaged(*FlagInfo, void){};
        defer checked_flags.deinit(self.allocator);
        var fit = self.flags.iterator();
        while (fit.next()) |entry| {
            const flag_info = entry.value_ptr.*;
            if (checked_flags.contains(flag_info)) continue;
            checked_flags.put(self.allocator, flag_info, {}) catch {};
            if (flag_info.required and flag_info.count == 0) {
                try self.appendError("Missing required flag: ", entry.key_ptr.*);
            }
        }
        var oit = self.options.iterator();
        while (oit.next()) |entry| {
            const opt = entry.value_ptr;
            const key = entry.key_ptr.*;
            if (opt.required) {
                const resolved = utils.resolveOptionAlias(key, self.option_aliases, self.short_options);
                if (!seen.contains(resolved) and opt.value.len == 0) {
                    try self.appendError("Missing required option: ", key);
                }
            }
        }
        for (self.positionals.items, 0..) |pos, idx| {
            if (pos.required and pos.value == null and pos.default == null) {
                try self.appendError("Missing required positional: ", pos.name);
            }
            if (positional_counts[idx] < pos.min_count) {
                try self.appendError("Too few values for positional: ", pos.name);
            }
            if (positional_counts[idx] > pos.max_count) {
                try self.appendError("Too many values for positional: ", pos.name);
            }
        }
        var mit = self.mutex_groups.iterator();
        while (mit.next()) |entry| {
            var count: usize = 0;
            for (entry.value_ptr.members.items) |m| {
                if (seen.contains(m)) count += 1;
            }
            if (count > 1) {
                try self.appendError("Mutually exclusive arguments used together in group: ", entry.key_ptr.*);
            }
        }
    }

    pub fn flagCount(self: *Parser, name: []const u8) usize {
        const resolved = utils.resolveFlagAlias(name, self.flag_aliases, self.short_flags);
        if (self.flags.get(resolved)) |flag_ptr| {
            if (self.flag_counts.get(flag_ptr)) |count| return count;
        }
        return 0;
    }

    pub fn flagPresent(self: *Parser, name: []const u8) bool {
        return self.flagCount(name) > 0;
    }

    pub fn getOption(self: *Parser, name: []const u8) ?[]const u8 {
        const resolved = utils.resolveOptionAlias(name, self.option_aliases, self.short_options);
        if (self.options.get(resolved)) |opt| {
            return opt.value;
        }
        return null;
    }

    pub fn printErrors(self: *Parser) void {
        for (self.errors.items) |err| {
            std.debug.print("Error: {s}\n", .{err});
        }
    }

    pub fn printHelp(self: *Parser) void {
        self.printHelpWithOptions(.flat);
    }

    pub fn printHelpWithOptions(self: *Parser, style: types.HelpStyle) void {
        switch (style) {
            .flat => self.printHelpFlat(),
            .simple_grouped => self.printHelpSimpleGrouped(),
            .complex_grouped => self.printHelpComplexGrouped(),
        }
    }

    fn getProgramName(self: *Parser) []const u8 {
        return self.program_name orelse if (self.args.len > 0) self.args[0] else "<program>";
    }

    fn printHelpFlat(self: *Parser) void {
        const prog = self.getProgramName();
        std.debug.print("Usage: {s} [options] [flags]", .{prog});
        if (self.positionals.items.len > 0) {
            for (self.positionals.items) |pos| {
                if (pos.hidden) continue;
                std.debug.print(" [{s}]", .{pos.name});
            }
        }
        std.debug.print("\n\n", .{});

        var it = self.options.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.hidden) continue;
            const opt = entry.value_ptr;
            var line_buf: [128]u8 = undefined;

            var short_name: ?[]const u8 = null;
            var short_it = self.short_options.iterator();
            while (short_it.next()) |short_entry| {
                if (std.mem.eql(u8, short_entry.value_ptr.*, entry.key_ptr.*)) {
                    short_name = short_entry.key_ptr.*;
                    break;
                }
            }

            const res = if (short_name) |s|
                std.fmt.bufPrint(&line_buf, "  {s}, {s}", .{ s, entry.key_ptr.* }) catch unreachable
            else
                std.fmt.bufPrint(&line_buf, "      {s}", .{entry.key_ptr.*}) catch unreachable;
            const line = line_buf[0..res.len];

            const pad_len = utils.padToColumn(&line_buf, line.len, 22);
            const padded_line = line_buf[0..pad_len];
            std.debug.print("{s}  {s}", .{ padded_line, opt.help });
            if (opt.default.len > 0) {
                std.debug.print(" (default: {s})", .{opt.default});
            }
            std.debug.print("\n", .{});
        }
        var fcit = self.flag_counts.iterator();
        while (fcit.next()) |entry| {
            const flag = entry.key_ptr.*;
            if (flag.hidden) continue;
            var line_buf: [128]u8 = undefined;
            var line: []u8 = undefined;

            var short_name: ?[]const u8 = null;
            var long_name: ?[]const u8 = null;
            var sf_it = self.short_flags.iterator();
            while (sf_it.next()) |sf_entry| {
                const key = sf_entry.key_ptr.*;
                const value = sf_entry.value_ptr.*;
                if (self.flags.get(value)) |ptr| {
                    if (ptr == flag) {
                        if (key.len == 2) {
                            short_name = key;
                        } else {
                            long_name = key;
                        }
                    }
                }
            }

            if (short_name) |s| {
                const res = if (long_name) |l|
                    std.fmt.bufPrint(&line_buf, "  {s}, {s}", .{ s, l }) catch unreachable
                else
                    std.fmt.bufPrint(&line_buf, "  {s}", .{s}) catch unreachable;
                line = line_buf[0..res.len];
            } else if (long_name) |l| {
                const res = std.fmt.bufPrint(&line_buf, "      {s}", .{l}) catch unreachable;
                line = line_buf[0..res.len];
            } else {
                line = &.{};
            }

            const pad_len = utils.padToColumn(&line_buf, line.len, 22);
            line = line_buf[0..pad_len];
            std.debug.print("{s}  {s}\n", .{ line, flag.help });
        }

        if (self.positionals.items.len > 0) {
            std.debug.print("Positionals:\n", .{});
            for (self.positionals.items) |pos| {
                if (pos.hidden) continue;
                std.debug.print("  {s}", .{pos.name});
                var pad: usize = 1;
                while (pad < 20 - pos.name.len) : (pad += 1) std.debug.print(" ", .{});
                std.debug.print("  {s}", .{pos.help});
                if (pos.min_count != 1 or pos.max_count != 1) {
                    std.debug.print(" (min: {d}, max: {d})", .{ pos.min_count, pos.max_count });
                }
                std.debug.print("\n", .{});
            }
        }
    }

    fn printHelpSimpleGrouped(self: *Parser) void {
        var group_map = std.StringHashMapUnmanaged(void){};
        var group_items = std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)){};
        defer group_map.deinit(self.allocator);
        defer group_items.deinit(self.allocator);
        var opt_it = self.options.iterator();
        while (opt_it.next()) |entry| {
            if (entry.value_ptr.hidden) continue;
            const group = entry.value_ptr.group orelse "(ungrouped)";
            if (!group_map.contains(group)) {
                group_map.put(self.allocator, group, {}) catch {};
                group_items.put(self.allocator, group, std.ArrayListUnmanaged([]const u8){}) catch {};
            }
            if (group_items.getPtr(group)) |arr| {
                arr.append(self.allocator, entry.key_ptr.*) catch {};
            }
        }
        var flag_groups = std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)){};
        defer flag_groups.deinit(self.allocator);
        var flag_it = self.flags.iterator();
        while (flag_it.next()) |entry| {
            if (entry.value_ptr.*.hidden) continue;
            const group = entry.value_ptr.*.group orelse "(ungrouped)";
            if (!flag_groups.contains(group)) {
                flag_groups.put(self.allocator, group, std.ArrayListUnmanaged([]const u8){}) catch {};
            }
            if (flag_groups.getPtr(group)) |arr| {
                arr.append(self.allocator, entry.key_ptr.*) catch {};
            }
        }
        const prog = self.getProgramName();
        std.debug.print("Usage: {s} [options] [flags]", .{prog});
        if (self.positionals.items.len > 0) {
            for (self.positionals.items) |pos| {
                if (pos.hidden) continue;
                std.debug.print(" [{s}]", .{pos.name});
            }
        }
        std.debug.print("\n\n", .{});
        std.debug.print("Options (grouped):\n", .{});
        var group_it = group_items.iterator();
        while (group_it.next()) |entry| {
            std.debug.print("\t[{s}]\n", .{entry.key_ptr.*});
            var max_opt_len: usize = 0;
            for (entry.value_ptr.items) |opt_name| {
                if (opt_name.len > max_opt_len) max_opt_len = opt_name.len;
            }
            for (entry.value_ptr.items) |opt_name| {
                if (self.options.get(opt_name)) |opt| {
                    if (opt.hidden) continue;
                    std.debug.print("\t\t{s}", .{opt_name});
                    var pad: usize = 1;
                    if (max_opt_len > opt_name.len) {
                        pad = ((max_opt_len - opt_name.len) / 8) + 1;
                    }
                    var i: usize = 0;
                    while (i < pad) : (i += 1) std.debug.print("\t", .{});
                    std.debug.print("{s}", .{opt.help});
                    if (opt.default.len > 0) {
                        std.debug.print("\t(default: {s})", .{opt.default});
                    }
                    std.debug.print("\n", .{});
                }
            }
        }
        std.debug.print("Flags (grouped):\n", .{});
        var flag_group_it = flag_groups.iterator();
        while (flag_group_it.next()) |entry| {
            std.debug.print("\t[{s}]\n", .{entry.key_ptr.*});
            var max_flag_len: usize = 0;
            for (entry.value_ptr.items) |flag_name| {
                if (flag_name.len > max_flag_len) max_flag_len = flag_name.len;
            }
            for (entry.value_ptr.items) |flag_name| {
                if (self.flags.get(flag_name)) |flag_ptr| {
                    if (flag_ptr.*.hidden) continue;
                    const flag = flag_ptr.*;
                    std.debug.print("\t\t{s}", .{flag_name});
                    var pad: usize = 1;
                    if (max_flag_len > flag_name.len) {
                        pad = ((max_flag_len - flag_name.len) / 8) + 1;
                    }
                    var i: usize = 0;
                    while (i < pad) : (i += 1) std.debug.print("\t", .{});
                    std.debug.print("{s}\n", .{flag.help});
                }
            }
        }
        if (self.positionals.items.len > 0) {
            std.debug.print("Positionals:\n", .{});
            var max_pos_len: usize = 0;
            for (self.positionals.items) |pos| {
                if (pos.hidden) continue;
                if (pos.name.len > max_pos_len) max_pos_len = pos.name.len;
            }
            for (self.positionals.items) |pos| {
                if (pos.hidden) continue;
                std.debug.print("\t{s}", .{pos.name});
                var pad: usize = 1;
                if (max_pos_len > pos.name.len) {
                    pad = ((max_pos_len - pos.name.len) / 8) + 1;
                }
                var i: usize = 0;
                while (i < pad) : (i += 1) std.debug.print("\t", .{});
                std.debug.print("{s}", .{pos.help});
                if (pos.min_count != 1 or pos.max_count != 1) {
                    std.debug.print("\t(min: {d}, max: {d})", .{ pos.min_count, pos.max_count });
                }
                std.debug.print("\n", .{});
            }
        }
    }

    fn printHelpComplexGrouped(self: *Parser) void {
        std.debug.print("[complex_grouped help output: show mutex groups and nested groupings here]\n", .{});
        self.printHelpFlat();
    }
};
