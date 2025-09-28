const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    // Register short and long flags/options
    try parser.addFlagWithShort("--help", "-h", "Show help message");
    try parser.addFlagWithShort("--verbose", "-v", "Increase verbosity");
    try parser.addOptionWithShort("--name", "-n", "World", "Name to greet");
    try parser.addOptionWithShort("--mode", "-m", "default", "Mode to use");
    // Register positional argument (required)
    try parser.addPositional("input", "Input file", true, null);
    // Register mutually exclusive group
    try parser.addMutexGroup("mode_group", &[_][]const u8{ "--mode", "--verbose" });
    // Mark --name as required
    try parser.setRequired("--name");
    try parser.parse();

    if (parser.errors.items.len > 0) {
        parser.printErrors();
        parser.printHelp();
        return;
    }
    if (parser.flagPresent("--help")) {
        parser.printHelp();
        return;
    }
    const name = parser.getOption("--name") orelse "World";
    const mode = parser.getOption("--mode") orelse "default";
    const verbosity = parser.flagCount("--verbose");
    var input: []const u8 = "(none)";
    if (parser.positionals.items.len > 0 and parser.positionals.items[0].value != null) {
        input = parser.positionals.items[0].value.?;
    }
    std.debug.print("Hello, {s}!\nMode: {s}\nVerbosity: {d}\nInput: {s}\n", .{ name, mode, verbosity, input });
}
