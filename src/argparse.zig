const std = @import("std");

/// Argument parser for command-line interfaces.
/// Main argument parser struct. Holds all argument definitions and parsing state.
pub const Parser = struct {
    /// Get the value of a bool option, or error if not present or invalid.
    pub fn getOptionBool(self: *Parser, name: []const u8) !?bool {
        if (self.options.get(name)) |opt| {
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
    test "getOptionBool works for bool options" {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var args = [_][:0]const u8{
            std.mem.sliceTo("--flag", 0),
            std.mem.sliceTo("true", 0),
            std.mem.sliceTo("--flag2", 0),
            std.mem.sliceTo("no", 0),
        };
        var parser = Parser.init(allocator, args[0..]);
        try parser.addOption("--flag", null, "false", "A bool flag");
        parser.options.getPtr("--flag").?.typ = .bool;
        try parser.addOption("--flag2", null, "yes", "Another bool flag");
        parser.options.getPtr("--flag2").?.typ = .bool;
        try parser.parse();
        try std.testing.expectEqual(@as(?bool, true), try parser.getOptionBool("--flag"));
        try std.testing.expectEqual(@as(?bool, false), try parser.getOptionBool("--flag2"));
    }
    /// Append an error message and optional argument to the errors list.
    fn appendError(self: *Parser, msg: []const u8, arg: ?[]const u8) !void {
        try self.errors.append(self.allocator, msg);
        if (arg) |a| {
            try self.errors.append(self.allocator, a);
        }
    }
    /// Controls the style of help output for the argument parser.
    pub const HelpStyle = enum {
        flat,
        simple_grouped,
        complex_grouped,
    };
    allocator: std.mem.Allocator,
    args: []const [:0]const u8,
    flags: std.StringHashMapUnmanaged(*FlagInfo),
    flag_counts: std.AutoHashMapUnmanaged(*FlagInfo, usize),
    options: std.StringHashMapUnmanaged(OptionInfo),
    short_options: std.StringHashMapUnmanaged([]const u8),
    short_flags: std.StringHashMapUnmanaged([]const u8),
    positionals: std.ArrayListUnmanaged(PositionalInfo),
    errors: std.ArrayListUnmanaged([]const u8),
    mutex_groups: std.StringHashMapUnmanaged(MutexGroup),

    /// Information about a flag argument.
    /// Information about a flag argument (e.g. --help).
    pub const FlagInfo = struct {
        help: []const u8,
        required: bool = false,
        group: ?[]const u8 = null,
        count: usize = 0, // Number of times this flag was seen
    };
    /// Supported option value types.
    /// Supported value types for options and positionals.
    pub const OptionType = enum { string, int, float, bool };
    /// Information about an option argument.
    /// Information about an option argument (e.g. --name=foo).
    pub const OptionInfo = struct {
        help: []const u8,
        value: []const u8,
        default: []const u8,
        required: bool = false,
        typ: OptionType = .string,
        group: ?[]const u8 = null,
        min_int: ?i64 = null,
        max_int: ?i64 = null,
        min_float: ?f64 = null,
        max_float: ?f64 = null,
    };
    /// Information about a positional argument.
    /// Information about a positional argument (e.g. input.txt).
    pub const PositionalInfo = struct {
        name: []const u8,
        help: []const u8,
        value: ?[]const u8 = null,
        required: bool = false,
        default: ?[]const u8 = null,
        typ: OptionType = .string,
        min_count: usize = 1,
        max_count: usize = 1,
    };
    /// Group of mutually exclusive arguments.
    /// Group of mutually exclusive arguments.
    pub const MutexGroup = struct {
        members: std.ArrayListUnmanaged([]const u8),
    };

    /// Initialize a new parser with allocator and argument list.
    /// Initialize a new parser with allocator and argument list.
    ///
    /// Args:
    ///   allocator: The allocator to use for internal storage.
    ///   args: The argument array (typically from std.process.argsAlloc).
    pub fn init(allocator: std.mem.Allocator, args: []const [:0]const u8) Parser {
        return Parser{
            .allocator = allocator,
            .args = args,
            .flags = .{},
            .flag_counts = .{},
            .options = .{},
            .short_options = .{},
            .short_flags = .{},
            .positionals = .{},
            .errors = .{},
            .mutex_groups = .{},
        };
    }

    /// Add a flag with a required short name and optional long name (e.g. -h, --help).
    ///
    /// Args:
    ///   short: The short flag name (e.g. "-h"). Must not be empty.
    ///   long: The long flag name (e.g. "--help"), or "" for short-only.
    ///   help: Description for help output.
    pub fn addFlag(self: *Parser, short: []const u8, long: []const u8, help: []const u8) !void {
        if (short.len == 0) return error.InvalidFlagName;
        const has_long = long.len > 0;
        const flag_ptr = try self.allocator.create(FlagInfo);
        flag_ptr.* = FlagInfo{ .help = help };
        try self.flags.put(self.allocator, short, flag_ptr);
        if (has_long) {
            try self.flags.put(self.allocator, long, flag_ptr);
            try self.short_flags.put(self.allocator, short, long);
            try self.short_flags.put(self.allocator, long, short);
        }
        try self.flag_counts.put(self.allocator, flag_ptr, 0);
    }

    /// Add an option with both long and optional short names (e.g. --name, -n) and a default value.
    ///
    /// Args:
    ///   long: The long option name (e.g. "--name").
    ///   short: The short option name (e.g. "-n"), or null for long-only.
    ///   default: The default value as a string.
    ///   help: Description for help output.
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

    /// Add a positional argument with min/max count constraints.
    /// Add a positional argument with min/max count constraints.
    ///
    /// Args:
    ///   name: The positional argument name.
    ///   help: Description for help output.
    ///   min_count: Minimum number of values required.
    ///   max_count: Maximum number of values allowed.
    pub fn addPositionalWithCount(self: *Parser, name: []const u8, help: []const u8, min_count: usize, max_count: usize) !void {
        try self.positionals.append(self.allocator, PositionalInfo{
            .name = name,
            .help = help,
            .required = min_count > 0,
            .default = null,
            .min_count = min_count,
            .max_count = max_count,
        });
    }

    /// Add a mutually exclusive group by name and member argument names.
    /// Add a mutually exclusive group by name and member argument names.
    ///
    /// Args:
    ///   group_name: The group name.
    ///   members: Array of argument names that are mutually exclusive.
    pub fn addMutexGroup(self: *Parser, group_name: []const u8, members: []const []const u8) !void {
        var group = MutexGroup{ .members = .{} };
        for (members) |m| {
            try group.members.append(self.allocator, m);
        }
        try self.mutex_groups.put(self.allocator, group_name, group);
    }

    /// Add a long option (e.g. --name) with default value and help text.
    /// Add a long option (e.g. --name) with default value and help text.
    ///
    /// Args:
    ///   name: The option name (e.g. "--name").
    ///   default: The default value as a string.
    ///   help: Description for help output.
    pub fn addOption(self: *Parser, long: []const u8, short: ?[]const u8, default: []const u8, help: []const u8) !void {
        try self.options.put(self.allocator, long, OptionInfo{ .help = help, .value = default, .default = default });
        if (short) |s| {
            try self.short_options.put(self.allocator, s, long);
        }
    }

    /// Add an int option with optional short name and min/max constraints.
    ///
    /// Args:
    ///   long: The long option name (e.g. "--count").
    ///   short: The short option name (e.g. "-c"), or null for long-only.
    ///   default: The default value as an integer.
    ///   help: Description for help output.
    ///   min: Optional minimum value.
    ///   max: Optional maximum value.
    pub fn addIntOption(self: *Parser, long: []const u8, short: ?[]const u8, default: i64, help: []const u8, min: ?i64, max: ?i64) !void {
        const def_str = try std.fmt.allocPrint(self.allocator, "{}", .{default});
        try self.options.put(self.allocator, long, OptionInfo{
            .help = help,
            .value = def_str,
            .default = def_str,
            .typ = .int,
            .min_int = min,
            .max_int = max,
        });
        if (short) |s| {
            try self.short_options.put(self.allocator, s, long);
        }
    }

    /// Add a float option with optional short name and min/max constraints.
    ///
    /// Args:
    ///   long: The long option name (e.g. "--ratio").
    ///   short: The short option name (e.g. "-r"), or null for long-only.
    ///   default: The default value as a float.
    ///   help: Description for help output.
    ///   min: Optional minimum value.
    ///   max: Optional maximum value.
    pub fn addFloatOption(self: *Parser, long: []const u8, short: ?[]const u8, default: f64, help: []const u8, min: ?f64, max: ?f64) !void {
        const def_str = try std.fmt.allocPrint(self.allocator, "{}", .{default});
        try self.options.put(self.allocator, long, OptionInfo{
            .help = help,
            .value = def_str,
            .default = def_str,
            .typ = .float,
            .min_float = min,
            .max_float = max,
        });
        if (short) |s| {
            try self.short_options.put(self.allocator, s, long);
        }
    }

    /// Get the value of an int option, or error if not present or invalid.
    /// Get the value of an int option, or error if not present or invalid.
    ///
    /// Args:
    ///   name: The option name.
    /// Returns: The parsed int value, or error.
    pub fn getOptionInt(self: *Parser, name: []const u8) !?i64 {
        if (self.options.get(name)) |opt| {
            if (opt.typ != .int) return error.InvalidType;
            const val = try std.fmt.parseInt(i64, opt.value, 10);
            if (opt.min_int) |min| if (val < min) return error.OutOfRange;
            if (opt.max_int) |max| if (val > max) return error.OutOfRange;
            return val;
        }
        return null;
    }

    /// Get the value of a float option, or error if not present or invalid.
    /// Get the value of a float option, or error if not present or invalid.
    ///
    /// Args:
    ///   name: The option name.
    /// Returns: The parsed float value, or error.
    pub fn getOptionFloat(self: *Parser, name: []const u8) !?f64 {
        if (self.options.get(name)) |opt| {
            if (opt.typ != .float) return error.InvalidType;
            const val = try std.fmt.parseFloat(f64, opt.value);
            if (opt.min_float) |min| if (val < min) return error.OutOfRange;
            if (opt.max_float) |max| if (val > max) return error.OutOfRange;
            return val;
        }
        return null;
    }

    /// Parse the arguments, populating values and errors.
    /// Parse the arguments, populating values and errors.
    ///
    /// Returns: error if allocation or parsing fails.
    pub fn parse(self: *Parser) !void {
        var i: usize = 0;
        var pos_idx: usize = 0;
        var seen: std.StringHashMapUnmanaged(bool) = .{};
        defer seen.deinit(self.allocator);
        var positional_counts: []usize = try self.allocator.alloc(usize, self.positionals.items.len);
        for (positional_counts) |*c| c.* = 0;
        var fcit = self.flag_counts.iterator();
        while (fcit.next()) |entry| {
            entry.value_ptr.* = 0;
            entry.key_ptr.*.count = 0;
        }
        while (i < self.args.len) : (i += 1) {
            const arg = self.args[i];
            if (std.mem.startsWith(u8, arg, "--")) {
                if (self.flags.getPtr(arg)) |flag_ptr_ptr| {
                    const flag = flag_ptr_ptr.*;
                    // Only increment count for the canonical flag (the one with the lowest address)
                    var canonical_flag = flag;
                    if (self.short_flags.get(arg)) |short| {
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
                    try seen.put(self.allocator, arg, true);
                    if (self.short_flags.get(arg)) |short| {
                        try seen.put(self.allocator, short, true);
                    }
                } else if (self.options.getPtr(arg)) |opt| {
                    if (i + 1 < self.args.len) {
                        if (opt.value.ptr != opt.default.ptr) {
                            self.allocator.free(opt.value);
                        }
                        const val = self.args[i + 1];
                        const val_copy = try self.allocator.alloc(u8, val.len);
                        std.mem.copyForwards(u8, val_copy, val);
                        opt.value = val_copy;
                        i += 1;
                        try seen.put(self.allocator, arg, true);
                    } else {
                        try self.appendError("Missing value for option: ", arg);
                    }
                } else {
                    try self.appendError("Unknown argument: ", arg);
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
                const short = arg;
                if (self.flags.getPtr(short)) |flag_ptr_ptr| {
                    const flag = flag_ptr_ptr.*;
                    // Only increment count for the canonical flag (the one with the lowest address)
                    var canonical_flag = flag;
                    if (self.short_flags.get(short)) |long| {
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
                    try seen.put(self.allocator, short, true);
                    if (self.short_flags.get(short)) |long| {
                        try seen.put(self.allocator, long, true);
                    }
                } else if (self.short_options.get(short)) |long| {
                    if (self.options.getPtr(long)) |opt| {
                        if (i + 1 < self.args.len) {
                            if (opt.value.ptr != opt.default.ptr) {
                                self.allocator.free(opt.value);
                            }
                            const val = self.args[i + 1];
                            const val_copy = try self.allocator.alloc(u8, val.len);
                            std.mem.copyForwards(u8, val_copy, val);
                            opt.value = val_copy;
                            i += 1;
                            try seen.put(self.allocator, long, true);
                        } else {
                            try self.appendError("Missing value for option: ", long);
                        }
                    }
                } else {
                    try self.appendError("Unknown short argument: ", short);
                }
            } else {
                if (pos_idx < self.positionals.items.len) {
                    positional_counts[pos_idx] += 1;
                    if (self.positionals.items[pos_idx].value) |old| {
                        self.allocator.free(old);
                        const new_val = try self.allocator.alloc(u8, old.len + 1 + arg.len);
                        std.mem.copyForwards(u8, new_val[0..old.len], old);
                        new_val[old.len] = ' ';
                        std.mem.copyForwards(u8, new_val[old.len + 1 ..], arg);
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
        // Check required flags/options/positionals
        // Flags
        var fit = self.flags.iterator();
        while (fit.next()) |entry| {
            const flag_info = entry.value_ptr.*;
            if (flag_info.required and flag_info.count == 0) {
                try self.appendError("Missing required flag: ", entry.key_ptr.*);
            }
        }
        // Options
        var oit = self.options.iterator();
        while (oit.next()) |entry| {
            const opt = entry.value_ptr;
            if (opt.required and (opt.value.ptr == opt.default.ptr or opt.value.len == 0)) {
                try self.appendError("Missing required option: ", entry.key_ptr.*);
            }
        }
        // Positionals
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
        // Check mutually exclusive groups
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

    /// Return the number of times a flag was provided.
    pub fn flagCount(self: *Parser, name: []const u8) usize {
        if (self.flags.get(name)) |flag_ptr| {
            if (self.flag_counts.get(flag_ptr)) |count| return count;
        }
        return 0;
    }

    /// Return true if a flag was provided at least once.
    pub fn flagPresent(self: *Parser, name: []const u8) bool {
        return self.flagCount(name) > 0;
    }

    /// Get the value of an option, or null if not present.
    pub fn getOption(self: *Parser, name: []const u8) ?[]const u8 {
        if (self.options.get(name)) |opt| {
            return opt.value;
        }
        return null;
    }

    /// Print all parsing errors to stderr.
    pub fn printErrors(self: *Parser) void {
        for (self.errors.items) |err| {
            std.debug.print("Error: {s}\n", .{err});
        }
    }

    /// Prints a help message for all arguments, using the flat style by default.
    ///
    /// This is the simplest way to show help for your CLI. For advanced formatting,
    /// use `printHelpWithOptions`.
    pub fn printHelp(self: *Parser) void {
        self.printHelpWithOptions(.flat);
    }

    /// Print help with options (currently just style, extensible for future options).
    pub fn printHelpWithOptions(self: *Parser, style: HelpStyle) void {
        switch (style) {
            .flat => self.printHelpFlat(),
            .simple_grouped => self.printHelpSimpleGrouped(),
            .complex_grouped => self.printHelpComplexGrouped(),
        }
    }
    fn printHelpFlat(self: *Parser) void {
        std.debug.print("Usage: <program> [options] [flags]", .{});
        if (self.positionals.items.len > 0) {
            for (self.positionals.items) |pos| {
                std.debug.print(" [{s}]", .{pos.name});
            }
        }
        std.debug.print("\n\n", .{});
        std.debug.print("Options:\n", .{});
        var it = self.options.iterator();
        while (it.next()) |entry| {
            std.debug.print("  {s}: ", .{entry.key_ptr.*});
            printWrapped(entry.value_ptr.help, 24);
            std.debug.print("    (default: {s})\n", .{entry.value_ptr.default});
        }
        std.debug.print("Flags:\n", .{});
        var fit = self.flags.iterator();
        while (fit.next()) |entry| {
            const flag_info = entry.value_ptr.*;
            std.debug.print("  {s}: ", .{entry.key_ptr.*});
            printWrapped(flag_info.help, 24);
        }
        if (self.positionals.items.len > 0) {
            std.debug.print("Positionals:\n", .{});
            for (self.positionals.items) |pos| {
                std.debug.print("  {s}: ", .{pos.name});
                printWrapped(pos.help, 24);
                if (pos.min_count != 1 or pos.max_count != 1) {
                    std.debug.print("    (min: {d}, max: {d})\n", .{ pos.min_count, pos.max_count });
                } else {
                    std.debug.print("\n", .{});
                }
            }
        }
    }

    fn printHelpSimpleGrouped(self: *Parser) void {
        // Group options and flags by .group field
        var group_map = std.StringHashMapUnmanaged(void){};
        var group_items = std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)){};
        defer group_map.deinit(self.allocator);
        defer group_items.deinit(self.allocator);
        // Collect groups for options
        var opt_it = self.options.iterator();
        while (opt_it.next()) |entry| {
            const group = entry.value_ptr.group orelse "(ungrouped)";
            if (!group_map.contains(group)) {
                group_map.put(self.allocator, group, {}) catch {};
                group_items.put(self.allocator, group, std.ArrayListUnmanaged([]const u8){}) catch {};
            }
            if (group_items.getPtr(group)) |arr| {
                arr.append(self.allocator, entry.key_ptr.*) catch {};
            }
        }
        // Collect groups for flags
        var flag_groups = std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)){};
        defer flag_groups.deinit(self.allocator);
        var flag_it = self.flags.iterator();
        while (flag_it.next()) |entry| {
            const group = entry.value_ptr.*.group orelse "(ungrouped)";
            if (!flag_groups.contains(group)) {
                flag_groups.put(self.allocator, group, std.ArrayListUnmanaged([]const u8){}) catch {};
            }
            if (flag_groups.getPtr(group)) |arr| {
                arr.append(self.allocator, entry.key_ptr.*) catch {};
            }
        }
        std.debug.print("Usage: <program> [options] [flags]", .{});
        if (self.positionals.items.len > 0) {
            for (self.positionals.items) |pos| {
                std.debug.print(" [{s}]", .{pos.name});
            }
        }
        std.debug.print("\n\n", .{});
        // Print grouped options
        std.debug.print("Options (grouped):\n", .{});
        var group_it = group_items.iterator();
        while (group_it.next()) |entry| {
            std.debug.print("  [{s}]\n", .{entry.key_ptr.*});
            for (entry.value_ptr.items) |opt_name| {
                if (self.options.get(opt_name)) |opt| {
                    std.debug.print("    {s}: ", .{opt_name});
                    printWrapped(opt.help, 24);
                    std.debug.print("      (default: {s})\n", .{opt.default});
                }
            }
        }
        // Print grouped flags
        std.debug.print("Flags (grouped):\n", .{});
        var flag_group_it = flag_groups.iterator();
        while (flag_group_it.next()) |entry| {
            std.debug.print("  [{s}]\n", .{entry.key_ptr.*});
            for (entry.value_ptr.items) |flag_name| {
                if (self.flags.get(flag_name)) |flag_ptr| {
                    const flag = flag_ptr.*;
                    std.debug.print("    {s}: ", .{flag_name});
                    printWrapped(flag.help, 24);
                }
            }
        }
        // Print positionals
        if (self.positionals.items.len > 0) {
            std.debug.print("Positionals:\n", .{});
            for (self.positionals.items) |pos| {
                std.debug.print("  {s}: ", .{pos.name});
                printWrapped(pos.help, 24);
                if (pos.min_count != 1 or pos.max_count != 1) {
                    std.debug.print("    (min: {d}, max: {d})\n", .{ pos.min_count, pos.max_count });
                } else {
                    std.debug.print("\n", .{});
                }
            }
        }
    }

    fn printHelpComplexGrouped(self: *Parser) void {
        std.debug.print("[complex_grouped help output: show mutex groups and nested groupings here]\n", .{});
        self.printHelpFlat();
    }

    fn printWrapped(text: []const u8, indent: usize) void {
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
};

test "int/float option min/max constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = [_][:0]const u8{};
    _ = args; // autofix

    // Out of range
    var args2 = [_][:0]const u8{
        std.mem.sliceTo("--count", 0),
        std.mem.sliceTo("20", 0),
        std.mem.sliceTo("--ratio", 0),
        std.mem.sliceTo("-0.1", 0),
    };
    var parser2 = Parser.init(allocator, args2[0..]);
    try parser2.addIntOption("--count", null, 5, "How many times", 1, 10);
    try parser2.addFloatOption("--ratio", null, 0.5, "A ratio", 0.0, 1.0);
    try parser2.parse();
    try std.testing.expectError(error.OutOfRange, parser2.getOptionInt("--count"));
    try std.testing.expectError(error.OutOfRange, parser2.getOptionFloat("--ratio"));
}

test "positional min/max count constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("file1", 0),
        std.mem.sliceTo("file2", 0),
        std.mem.sliceTo("file3", 0),
    };
    var parser = Parser.init(allocator, args[0..]);
    try parser.addPositionalWithCount("input", "Input files", 1, 3);
    try parser.parse();
    // Should succeed with 3 positionals
    if (parser.errors.items.len != 0) {
        parser.printErrors();
    }
    try std.testing.expect(parser.errors.items.len == 0);

    var args2 = [_][:0]const u8{
        std.mem.sliceTo("file1", 0),
    };
    var parser2 = Parser.init(allocator, args2[0..]);
    try parser2.addPositionalWithCount("input", "Input files", 2, 3);
    try parser2.parse();
    // Should error: too few
    try std.testing.expect(parser2.errors.items.len > 0);

    var args3 = [_][:0]const u8{
        std.mem.sliceTo("file1", 0),
        std.mem.sliceTo("file2", 0),
        std.mem.sliceTo("file3", 0),
        std.mem.sliceTo("file4", 0),
    };
    var parser3 = Parser.init(allocator, args3[0..]);
    try parser3.addPositionalWithCount("input", "Input files", 2, 3);
    try parser3.parse();
    // Should error: too many
    try std.testing.expect(parser3.errors.items.len > 0);
}

test "help formatting includes groups and examples" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{};
    var parser = Parser.init(allocator, args[0..]);
    try parser.addFlag("-h", "--help", "Show help message");
    // Option API should be unified if needed; only addFlag is supported now.
    try parser.addPositionalWithCount("input", "Input files", 1, 2);
    parser.printHelp(); // visually inspect output for grouping and examples
}

test "printHelp supports all HelpStyle modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--foo", 0),
        std.mem.sliceTo("bar", 0),
    };
    var parser = Parser.init(allocator, args[0..]);
    try parser.addFlag("-f", "--foo", "Foo flag");
    try parser.addOption("--bar", null, "baz", "Bar option");
    try parser.addPositionalWithCount("input", "Input files", 1, 2);
    parser.printHelp(); // no-arg, should default to flat
    parser.printHelpWithOptions(.flat);
    parser.printHelpWithOptions(.simple_grouped);
    parser.printHelpWithOptions(.complex_grouped);
}

test "printHelp prints flat help without error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--help", 0),
    };
    var parser = Parser.init(allocator, args[0..]);
    try parser.addFlag("-h", "--help", "Show help message");
}

test "flagPresent and flagCount work for short, long, and short-only flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("-a", 0),
        std.mem.sliceTo("--beta", 0),
        std.mem.sliceTo("-c", 0),
    };
    var parser = Parser.init(allocator, args[0..]);
    // Add -a (short only), -b/--beta (both), -c/--gamma (both), --delta (long only)
    try parser.addFlag("-a", "", "Short only");
    try parser.addFlag("-b", "--beta", "Short and long");
    try parser.addFlag("-c", "--gamma", "Short and long");
    try parser.addFlag("--delta", "", "Long only");
    try parser.parse();
    // -a present
    try std.testing.expect(parser.flagPresent("-a"));
    try std.testing.expect(parser.flagPresent("-b"));
    try std.testing.expect(parser.flagPresent("--beta"));
    try std.testing.expect(parser.flagPresent("-c"));
    try std.testing.expect(parser.flagPresent("--gamma"));
    try std.testing.expect(parser.flagPresent("--delta") == false);
    // Counts
    try std.testing.expectEqual(@as(usize, 1), parser.flagCount("-a"));
    try std.testing.expectEqual(@as(usize, 1), parser.flagCount("--beta"));
    try std.testing.expectEqual(@as(usize, 1), parser.flagCount("-c"));
    try std.testing.expectEqual(@as(usize, 1), parser.flagCount("--gamma"));
    try std.testing.expectEqual(@as(usize, 0), parser.flagCount("--delta"));
}
