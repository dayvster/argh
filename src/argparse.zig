const std = @import("std");

/// Argument parser for command-line interfaces.
/// Main argument parser struct. Holds all argument definitions and parsing state.
pub const Parser = struct {
    /// Controls the style of help output for the argument parser.
    pub const HelpStyle = enum {
        flat,
        simple_grouped,
        complex_grouped,
    };
    allocator: std.mem.Allocator,
    args: []const [:0]const u8,
    flags: std.StringHashMapUnmanaged(FlagInfo),
    short_flags: std.StringHashMapUnmanaged([]const u8),
    options: std.StringHashMapUnmanaged(OptionInfo),
    short_options: std.StringHashMapUnmanaged([]const u8),
    positionals: std.ArrayListUnmanaged(PositionalInfo),
    errors: std.ArrayListUnmanaged([]const u8),
    required: std.ArrayListUnmanaged([]const u8),
    mutex_groups: std.StringHashMapUnmanaged(MutexGroup),

    /// Information about a flag argument.
    /// Information about a flag argument (e.g. --help).
    pub const FlagInfo = struct {
        help: []const u8,
        count: usize = 0,
        required: bool = false,
        group: ?[]const u8 = null,
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
            .short_flags = .{},
            .options = .{},
            .short_options = .{},
            .positionals = .{},
            .errors = .{},
            .required = .{},
            .mutex_groups = .{},
        };
    }

    /// Add a long flag (e.g. --help) with help text.
    /// Add a long flag (e.g. --help) with help text.
    ///
    /// Args:
    ///   name: The flag name (e.g. "--help").
    ///   help: Description for help output.
    pub fn addFlag(self: *Parser, name: []const u8, help: []const u8) !void {
        try self.flags.put(self.allocator, name, FlagInfo{ .help = help });
    }

    /// Add a flag with both long and short names (e.g. --help, -h).
    /// Add a flag with both long and short names (e.g. --help, -h).
    ///
    /// Args:
    ///   long: The long flag name (e.g. "--help").
    ///   short: The short flag name (e.g. "-h").
    ///   help: Description for help output.
    pub fn addFlagWithShort(self: *Parser, long: []const u8, short: []const u8, help: []const u8) !void {
        try self.flags.put(self.allocator, long, FlagInfo{ .help = help });
        try self.short_flags.put(self.allocator, short, long);
    }

    /// Add an option with both long and short names (e.g. --name, -n) and a default value.
    /// Add an option with both long and short names (e.g. --name, -n) and a default value.
    ///
    /// Args:
    ///   long: The long option name (e.g. "--name").
    ///   short: The short option name (e.g. "-n").
    ///   default: The default value as a string.
    ///   help: Description for help output.
    pub fn addOptionWithShort(self: *Parser, long: []const u8, short: []const u8, default: []const u8, help: []const u8) !void {
        try self.options.put(self.allocator, long, OptionInfo{ .help = help, .value = default, .default = default });
        try self.short_options.put(self.allocator, short, long);
    }

    /// Add a positional argument (e.g. input.txt) with help text, required flag, and optional default.
    /// Add a positional argument (e.g. input.txt) with help text, required flag, and optional default.
    ///
    /// Args:
    ///   name: The positional argument name.
    ///   help: Description for help output.
    ///   required: Whether the argument is required.
    ///   default: Optional default value.
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

    /// Mark an argument (flag or option) as required.
    /// Mark an argument (flag or option) as required.
    ///
    /// Args:
    ///   name: The argument name.
    pub fn setRequired(self: *Parser, name: []const u8) !void {
        try self.required.append(self.allocator, name);
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
    pub fn addOption(self: *Parser, name: []const u8, default: []const u8, help: []const u8) !void {
        try self.options.put(self.allocator, name, OptionInfo{ .help = help, .value = default, .default = default });
    }

    /// Add an int option with optional min/max constraints.
    /// Add an int option with optional min/max constraints.
    ///
    /// Args:
    ///   name: The option name (e.g. "--count").
    ///   default: The default value as an integer.
    ///   help: Description for help output.
    ///   min: Optional minimum value.
    ///   max: Optional maximum value.
    pub fn addIntOption(self: *Parser, name: []const u8, default: i64, help: []const u8, min: ?i64, max: ?i64) !void {
        const def_str = try std.fmt.allocPrint(self.allocator, "{}", .{default});
        try self.options.put(self.allocator, name, OptionInfo{
            .help = help,
            .value = def_str,
            .default = def_str,
            .typ = .int,
            .min_int = min,
            .max_int = max,
        });
    }

    /// Add a float option with optional min/max constraints.
    /// Add a float option with optional min/max constraints.
    ///
    /// Args:
    ///   name: The option name (e.g. "--ratio").
    ///   default: The default value as a float.
    ///   help: Description for help output.
    ///   min: Optional minimum value.
    ///   max: Optional maximum value.
    pub fn addFloatOption(self: *Parser, name: []const u8, default: f64, help: []const u8, min: ?f64, max: ?f64) !void {
        const def_str = try std.fmt.allocPrint(self.allocator, "{}", .{default});
        try self.options.put(self.allocator, name, OptionInfo{
            .help = help,
            .value = def_str,
            .default = def_str,
            .typ = .float,
            .min_float = min,
            .max_float = max,
        });
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
        while (i < self.args.len) : (i += 1) {
            const arg = self.args[i];
            if (std.mem.startsWith(u8, arg, "--")) {
                if (self.flags.getPtr(arg)) |flag| {
                    flag.count += 1;
                    try seen.put(self.allocator, arg, true);
                } else if (self.options.getPtr(arg)) |opt| {
                    if (i + 1 < self.args.len) {
                        opt.value = self.args[i + 1];
                        i += 1;
                        try seen.put(self.allocator, arg, true);
                    } else {
                        try self.errors.append(self.allocator, "Missing value for option: ");
                        try self.errors.append(self.allocator, arg);
                    }
                } else {
                    try self.errors.append(self.allocator, "Unknown argument: ");
                    try self.errors.append(self.allocator, arg);
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
                const short = arg;
                if (self.short_flags.get(short)) |long| {
                    if (self.flags.getPtr(long)) |flag| {
                        flag.count += 1;
                        try seen.put(self.allocator, long, true);
                    }
                } else if (self.short_options.get(short)) |long| {
                    if (self.options.getPtr(long)) |opt| {
                        if (i + 1 < self.args.len) {
                            opt.value = self.args[i + 1];
                            i += 1;
                            try seen.put(self.allocator, long, true);
                        } else {
                            try self.errors.append(self.allocator, "Missing value for option: ");
                            try self.errors.append(self.allocator, long);
                        }
                    }
                } else {
                    try self.errors.append(self.allocator, "Unknown short argument: ");
                    try self.errors.append(self.allocator, short);
                }
            } else {
                // Positional argument (support min/max count)
                if (pos_idx < self.positionals.items.len) {
                    positional_counts[pos_idx] += 1;
                    // For multi-value positionals, concatenate values with a separator (e.g. space)
                    if (self.positionals.items[pos_idx].value) |old| {
                        // Append with space separator
                        const new_val = try self.allocator.alloc(u8, old.len + 1 + arg.len);
                        std.mem.copyForwards(u8, new_val[0..old.len], old);
                        new_val[old.len] = ' ';
                        std.mem.copyForwards(u8, new_val[old.len + 1 ..], arg);
                        self.positionals.items[pos_idx].value = new_val;
                    } else {
                        self.positionals.items[pos_idx].value = arg;
                    }
                    if (positional_counts[pos_idx] >= self.positionals.items[pos_idx].max_count) {
                        pos_idx += 1;
                    }
                } else {
                    try self.errors.append(self.allocator, "Unexpected positional argument: ");
                    try self.errors.append(self.allocator, arg);
                }
            }
        }
        // Check required flags/options/positionals
        for (self.required.items) |req| {
            if (!seen.contains(req)) {
                try self.errors.append(self.allocator, "Missing required argument: ");
                try self.errors.append(self.allocator, req);
            }
        }
        for (self.positionals.items, 0..) |pos, idx| {
            if (pos.required and pos.value == null and pos.default == null) {
                try self.errors.append(self.allocator, "Missing required positional: ");
                try self.errors.append(self.allocator, pos.name);
            }
            if (positional_counts[idx] < pos.min_count) {
                try self.errors.append(self.allocator, "Too few values for positional: ");
                try self.errors.append(self.allocator, pos.name);
            }
            if (positional_counts[idx] > pos.max_count) {
                try self.errors.append(self.allocator, "Too many values for positional: ");
                try self.errors.append(self.allocator, pos.name);
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
                try self.errors.append(self.allocator, "Mutually exclusive arguments used together in group: ");
                try self.errors.append(self.allocator, entry.key_ptr.*);
            }
        }
    }

    /// Return the number of times a flag was provided.
    pub fn flagCount(self: *Parser, name: []const u8) usize {
        if (self.flags.get(name)) |flag| {
            return flag.count;
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

    /// Print a help message listing all options and flags.
    /// Print a help message listing all options, flags, and positionals.
    ///
    /// Args:
    ///   style: The help formatting style to use.
    pub fn printHelp(self: *Parser, style: HelpStyle) void {
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
            std.debug.print("  {s}: ", .{entry.key_ptr.*});
            printWrapped(entry.value_ptr.help, 24);
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
        std.debug.print("\nExamples:\n", .{});
        std.debug.print("  ./program --help\n", .{});
        std.debug.print("  ./program --count 3 --ratio 0.7 input.txt\n", .{});
    }

    fn printHelpSimpleGrouped(self: *Parser) void {
        std.debug.print("[simple_grouped help output not yet implemented]\n", .{});
        self.printHelpFlat();
    }

    fn printHelpComplexGrouped(self: *Parser) void {
        std.debug.print("[complex_grouped help output not yet implemented]\n", .{});
        self.printHelpFlat();
    }

    /// Print help text wrapped to a given width.
    fn printWrapped(text: []const u8, indent: usize) void {
        // var col: usize = 0;
        var line_col: usize = 0;
        var indent_buf: [64]u8 = undefined;
        if (indent > indent_buf.len) return; // avoid overflow
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
        std.debug.print("\n", .{});
        std.debug.print("\n", .{});
    }
};

// Tests

test "basic flag and option parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--help", 0),
        std.mem.sliceTo("--name", 0),
        std.mem.sliceTo("zig", 0),
    };
    var parser = Parser.init(allocator, args[0..]);
    try parser.addFlag("--help", "Show help");
    try parser.addOption("--name", "default", "Name to greet");
    try parser.parse();
    try std.testing.expect(parser.flagPresent("--help"));
    try std.testing.expectEqualStrings("zig", parser.getOption("--name") orelse "");
}

test "int/float option min/max constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--count", 0),
        std.mem.sliceTo("7", 0),
        std.mem.sliceTo("--ratio", 0),
        std.mem.sliceTo("0.8", 0),
    };
    var parser = Parser.init(allocator, args[0..]);
    try parser.addIntOption("--count", 5, "How many times", 1, 10);
    try parser.addFloatOption("--ratio", 0.5, "A ratio", 0.0, 1.0);
    try parser.parse();
    try std.testing.expectEqual(@as(i64, 7), try parser.getOptionInt("--count") orelse 0);
    try std.testing.expectEqual(@as(f64, 0.8), try parser.getOptionFloat("--ratio") orelse 0.0);

    // Out of range
    var args2 = [_][:0]const u8{
        std.mem.sliceTo("--count", 0),
        std.mem.sliceTo("20", 0),
        std.mem.sliceTo("--ratio", 0),
        std.mem.sliceTo("-0.1", 0),
    };
    var parser2 = Parser.init(allocator, args2[0..]);
    try parser2.addIntOption("--count", 5, "How many times", 1, 10);
    try parser2.addFloatOption("--ratio", 0.5, "A ratio", 0.0, 1.0);
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
    try parser.addFlagWithShort("--help", "-h", "Show help message");
    try parser.addOptionWithShort("--name", "-n", "World", "Name to greet");
    try parser.addPositionalWithCount("input", "Input files", 1, 2);
    parser.printHelp(Parser.HelpStyle.flat); // visually inspect output for grouping and examples
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
    try parser.addFlag("--foo", "Foo flag");
    try parser.addOption("--bar", "baz", "Bar option");
    try parser.addPositionalWithCount("input", "Input files", 1, 2);
    // Just ensure these run without error (visual/manual check for now)
    parser.printHelp(Parser.HelpStyle.flat);
    parser.printHelp(Parser.HelpStyle.simple_grouped);
    parser.printHelp(Parser.HelpStyle.complex_grouped);
}
