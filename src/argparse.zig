const std = @import("std");

/// Argument parser for command-line interfaces.
/// Main argument parser struct. Holds all argument definitions and parsing state.
pub const Parser = struct {
    allocator: std.mem.Allocator,
    args: []const [:0]u8,
    flags: std.StringHashMapUnmanaged(FlagInfo),
    short_flags: std.StringHashMapUnmanaged([]const u8),
    options: std.StringHashMapUnmanaged(OptionInfo),
    short_options: std.StringHashMapUnmanaged([]const u8),
    positionals: std.ArrayListUnmanaged(PositionalInfo),
    errors: std.ArrayListUnmanaged([]const u8),
    required: std.ArrayListUnmanaged([]const u8),
    mutex_groups: std.StringHashMapUnmanaged(MutexGroup),

    /// Information about a flag argument.
    pub const FlagInfo = struct {
        help: []const u8,
        count: usize = 0,
        required: bool = false,
        group: ?[]const u8 = null,
    };
    /// Supported option value types.
    pub const OptionType = enum { string, int, bool };
    /// Information about an option argument.
    pub const OptionInfo = struct {
        help: []const u8,
        value: []const u8,
        default: []const u8,
        required: bool = false,
        typ: OptionType = .string,
        group: ?[]const u8 = null,
    };
    /// Information about a positional argument.
    pub const PositionalInfo = struct {
        name: []const u8,
        help: []const u8,
        value: ?[]const u8 = null,
        required: bool = false,
        default: ?[]const u8 = null,
        typ: OptionType = .string,
    };
    /// Group of mutually exclusive arguments.
    pub const MutexGroup = struct {
        members: std.ArrayListUnmanaged([]const u8),
    };

    /// Initialize a new parser with allocator and argument list.
    pub fn init(allocator: std.mem.Allocator, args: []const [:0]u8) Parser {
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
    pub fn addFlag(self: *Parser, name: []const u8, help: []const u8) !void {
        try self.flags.put(self.allocator, name, FlagInfo{ .help = help });
    }

    /// Add a flag with both long and short names (e.g. --help, -h).
    pub fn addFlagWithShort(self: *Parser, long: []const u8, short: []const u8, help: []const u8) !void {
        try self.flags.put(self.allocator, long, FlagInfo{ .help = help });
        try self.short_flags.put(self.allocator, short, long);
    }

    /// Add an option with both long and short names (e.g. --name, -n) and a default value.
    pub fn addOptionWithShort(self: *Parser, long: []const u8, short: []const u8, default: []const u8, help: []const u8) !void {
        try self.options.put(self.allocator, long, OptionInfo{ .help = help, .value = default, .default = default });
        try self.short_options.put(self.allocator, short, long);
    }

    /// Add a positional argument (e.g. input.txt) with help text, required flag, and optional default.
    pub fn addPositional(self: *Parser, name: []const u8, help: []const u8, required: bool, default: ?[]const u8) !void {
        try self.positionals.append(self.allocator, PositionalInfo{
            .name = name,
            .help = help,
            .required = required,
            .default = default,
        });
    }

    /// Mark an argument (flag or option) as required.
    pub fn setRequired(self: *Parser, name: []const u8) !void {
        try self.required.append(self.allocator, name);
    }

    /// Add a mutually exclusive group by name and member argument names.
    pub fn addMutexGroup(self: *Parser, group_name: []const u8, members: []const []const u8) !void {
        var group = MutexGroup{ .members = .{} };
        for (members) |m| {
            try group.members.append(self.allocator, m);
        }
        try self.mutex_groups.put(self.allocator, group_name, group);
    }

    /// Add a long option (e.g. --name) with default value and help text.
    pub fn addOption(self: *Parser, name: []const u8, default: []const u8, help: []const u8) !void {
        try self.options.put(self.allocator, name, OptionInfo{ .help = help, .value = default, .default = default });
    }

    /// Parse the arguments, populating values and errors.
    pub fn parse(self: *Parser) !void {
        var i: usize = 1;
        var pos_idx: usize = 0;
        var seen: std.StringHashMapUnmanaged(bool) = .{};
        defer seen.deinit(self.allocator);
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
                // Positional argument
                if (pos_idx < self.positionals.items.len) {
                    self.positionals.items[pos_idx].value = arg;
                    pos_idx += 1;
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
        for (self.positionals.items) |pos| {
            if (pos.required and pos.value == null and pos.default == null) {
                try self.errors.append(self.allocator, "Missing required positional: ");
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
    pub fn printHelp(self: *Parser) void {
        std.debug.print("Options:\n", .{});
        var it = self.options.iterator();
        while (it.next()) |entry| {
            std.debug.print("  {s}: {s} (default: {s})\n", .{ entry.key_ptr.*, entry.value_ptr.help, entry.value_ptr.default });
        }
        std.debug.print("Flags:\n", .{});
        var fit = self.flags.iterator();
        while (fit.next()) |entry| {
            std.debug.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.help });
        }
    }
};

// Example test

test "basic flag and option parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][]const u8{ "--help", "--name", "zig" };
    var parser = Parser.init(allocator, &args);
    try parser.addFlag("--help");
    try parser.addOption("--name", "default");
    try parser.parse();
    try std.testing.expect(parser.flagPresent("--help"));
    try std.testing.expectEqualStrings("zig", parser.getOption("--name") orelse "");
}
