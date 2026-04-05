const std = @import("std");
const parser = @import("../parser/parser.zig");

test "subcommand parsing and dispatch works" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = [_][:0]const u8{
        std.mem.sliceTo("add", 0),
        std.mem.sliceTo("--name", 0),
        std.mem.sliceTo("foo", 0),
    };
    var main = parser.Parser.init(allocator, args[0..]);
    var add_args = [_][:0]const u8{};
    var add_parser = parser.Parser.init(allocator, add_args[0..]);
    try add_parser.addOption("--name", null, "", "Name to add");
    try main.subcommands.put(allocator, "add", &add_parser);
    var remove_args = [_][:0]const u8{};
    var remove_parser = parser.Parser.init(allocator, remove_args[0..]);
    try remove_parser.addOption("--id", null, "", "ID to remove");
    try main.subcommands.put(allocator, "remove", &remove_parser);

    const dispatched = try main.parseWithSubcommand();
    try std.testing.expect(dispatched == &add_parser);
    try std.testing.expectEqualStrings("foo", add_parser.options.get("--name").?.value);

    var args2 = [_][:0]const u8{
        std.mem.sliceTo("remove", 0),
        std.mem.sliceTo("--id", 0),
        std.mem.sliceTo("42", 0),
    };
    main.args = args2[0..];
    const dispatched2 = try main.parseWithSubcommand();
    try std.testing.expect(dispatched2 == &remove_parser);
    try std.testing.expectEqualStrings("42", remove_parser.options.get("--id").?.value);

    var args3 = [_][:0]const u8{
        std.mem.sliceTo("--foo", 0),
    };
    main.args = args3[0..];
    const dispatched3 = try main.parseWithSubcommand();
    try std.testing.expect(dispatched3 == null);
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
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addOption("--flag", null, "false", "A bool flag");
    p.options.getPtr("--flag").?.typ = .bool;
    try p.addOption("--flag2", null, "yes", "Another bool flag");
    p.options.getPtr("--flag2").?.typ = .bool;
    try p.parse();
    try std.testing.expectEqual(@as(?bool, true), try p.getOptionBool("--flag"));
    try std.testing.expectEqual(@as(?bool, false), try p.getOptionBool("--flag2"));
}

test "int/float option min/max constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args2 = [_][:0]const u8{
        std.mem.sliceTo("--count", 0),
        std.mem.sliceTo("20", 0),
        std.mem.sliceTo("--ratio", 0),
        std.mem.sliceTo("-0.1", 0),
    };
    var parser2 = parser.Parser.init(allocator, args2[0..]);
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
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addPositionalWithCount("input", "Input files", 1, 3);
    try p.parse();
    try std.testing.expect(p.errors.items.len == 0);
    var args2 = [_][:0]const u8{std.mem.sliceTo("file1", 0)};
    var parser2 = parser.Parser.init(allocator, args2[0..]);
    try parser2.addPositionalWithCount("input", "Input files", 2, 3);
    try parser2.parse();
    try std.testing.expect(parser2.errors.items.len > 0);
    var args3 = [_][:0]const u8{
        std.mem.sliceTo("file1", 0),
        std.mem.sliceTo("file2", 0),
        std.mem.sliceTo("file3", 0),
        std.mem.sliceTo("file4", 0),
    };
    var parser3 = parser.Parser.init(allocator, args3[0..]);
    try parser3.addPositionalWithCount("input", "Input files", 2, 3);
    try parser3.parse();
    try std.testing.expect(parser3.errors.items.len > 0);
}

test "help formatting includes groups and examples" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{};
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addFlag("-h", "--help", "Show help message");
    try p.addPositionalWithCount("input", "Input files", 1, 2);
    p.printHelp();
}

test "printHelp supports all HelpStyle modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--foo", 0),
        std.mem.sliceTo("bar", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addFlag("-f", "--foo", "Foo flag");
    try p.addOption("--bar", null, "baz", "Bar option");
    try p.addPositionalWithCount("input", "Input files", 1, 2);
    p.printHelp();
    p.printHelpWithOptions(.flat);
    p.printHelpWithOptions(.simple_grouped);
    p.printHelpWithOptions(.complex_grouped);
}

test "printHelp prints flat help without error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{std.mem.sliceTo("--help", 0)};
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addFlag("-h", "--help", "Show help message");
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
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addFlag("-a", "", "Short only");
    try p.addFlag("-b", "--beta", "Short and long");
    try p.addFlag("-c", "--gamma", "Short and long");
    try p.addFlag("--delta", "", "Long only");
    try p.parse();
    try std.testing.expect(p.flagPresent("-a"));
    try std.testing.expect(p.flagPresent("-b"));
    try std.testing.expect(p.flagPresent("--beta"));
    try std.testing.expect(p.flagPresent("-c"));
    try std.testing.expect(p.flagPresent("--gamma"));
    try std.testing.expect(p.flagPresent("--delta") == false);
    try std.testing.expectEqual(@as(usize, 1), p.flagCount("-a"));
    try std.testing.expectEqual(@as(usize, 1), p.flagCount("--beta"));
    try std.testing.expectEqual(@as(usize, 1), p.flagCount("-c"));
    try std.testing.expectEqual(@as(usize, 1), p.flagCount("--gamma"));
    try std.testing.expectEqual(@as(usize, 0), p.flagCount("--delta"));
}

test "hidden flags are parsed but not shown in help" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--hidden-flag", 0),
        std.mem.sliceTo("--visible-flag", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addHiddenFlag("-s", "--hidden-flag", "This should be hidden");
    try p.addFlag("-v", "--visible-flag", "This should be visible");
    try p.parse();
    try std.testing.expect(p.flagPresent("--hidden-flag"));
    try std.testing.expect(p.flagPresent("--visible-flag"));
}

test "hidden options are parsed but not shown in help" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--hidden-opt", 0),
        std.mem.sliceTo("secret", 0),
        std.mem.sliceTo("--visible-opt", 0),
        std.mem.sliceTo("visible", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addHiddenOption("--hidden-opt", null, "", "Hidden option");
    try p.addOption("--visible-opt", null, "", "Visible option");
    try p.parse();
    try std.testing.expectEqualStrings("secret", p.getOption("--hidden-opt").?);
    try std.testing.expectEqualStrings("visible", p.getOption("--visible-opt").?);
}

test "hidden positional arguments are parsed but not shown in help" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("visible", 0),
        std.mem.sliceTo("hidden", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addPositionalWithCount("visible", "Visible positional", 1, 1);
    try p.addHiddenPositionalWithCount("hidden", "Hidden positional", 1, 1);
    try p.parse();
    try std.testing.expect(p.positionals.items[0].value != null);
    try std.testing.expect(p.positionals.items[1].value != null);
}

test "hidden int and float options work" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--hidden-int", 0),
        std.mem.sliceTo("42", 0),
        std.mem.sliceTo("--hidden-float", 0),
        std.mem.sliceTo("3.14", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addHiddenIntOption("--hidden-int", null, 0, "Hidden int", null, null);
    try p.addHiddenFloatOption("--hidden-float", null, 0.0, "Hidden float", null, null);
    try p.parse();
    try std.testing.expectEqual(@as(?i64, 42), try p.getOptionInt("--hidden-int"));
    try std.testing.expectEqual(@as(?f64, 3.14), try p.getOptionFloat("--hidden-float"));
}

test "option aliases work for long options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--alias-name", 0),
        std.mem.sliceTo("value", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addOption("--name", null, "default", "The name");
    try p.addOptionAlias("--alias-name", "--name");
    try p.parse();
    try std.testing.expectEqualStrings("value", p.getOption("--name").?);
}

test "flag aliases work" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{std.mem.sliceTo("--chatty", 0)};
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addFlag("-v", "--verbose", "Verbose output");
    try p.addFlagAlias("--chatty", "--verbose");
    try p.parse();
    try std.testing.expect(p.flagPresent("--verbose"));
}

test "short option aliases work" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("-n", 0),
        std.mem.sliceTo("value", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addOption("--name", null, "default", "The name");
    try p.addOptionAlias("-n", "--name");
    try p.parse();
    try std.testing.expectEqualStrings("value", p.getOption("--name").?);
}

test "alias conflict is detected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var p = parser.Parser.init(allocator, &.{});
    try p.addOption("--name", null, "default", "The name");
    try std.testing.expectError(error.AliasConflict, p.addOptionAlias("--name", "--name"));
    try p.addOption("--conflict", null, "default", "A conflicting option");
    try std.testing.expectError(error.AliasConflict, p.addOptionAlias("--conflict", "--name"));
}

test "querying option by alias returns value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{
        std.mem.sliceTo("--alias-name", 0),
        std.mem.sliceTo("value", 0),
    };
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addOption("--name", null, "default", "The name");
    try p.addOptionAlias("--alias-name", "--name");
    try p.parse();
    try std.testing.expectEqualStrings("value", p.getOption("--alias-name").?);
}

test "querying flag by alias returns true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = [_][:0]const u8{std.mem.sliceTo("--chatty", 0)};
    var p = parser.Parser.init(allocator, args[0..]);
    try p.addFlag("-v", "--verbose", "Verbose output");
    try p.addFlagAlias("--chatty", "--verbose");
    try p.parse();
    try std.testing.expect(p.flagPresent("--chatty"));
}
