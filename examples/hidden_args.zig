const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addFlag("-h", "--help", "Show this help message");
    try parser.addOption("--name", null, "World", "Name to greet");
    try parser.addHiddenOption("--debug-secret", null, "", "Hidden debug option (not shown in help)");
    try parser.addHiddenFlag("-d", "--hidden-flag", "A hidden flag");
    try parser.addPositionalWithCount("input", "Input file", 1, 1);
    try parser.addHiddenPositionalWithCount("secret", "Hidden positional argument", 1, 1);
    try parser.parse();

    if (parser.flagPresent("--help")) {
        parser.printHelp();
        return;
    }

    const name = parser.getOption("--name") orelse "World";
    const debug_secret = parser.getOption("--debug-secret");
    if (debug_secret) |secret| {
        std.debug.print("Debug secret: {s}\n", .{secret});
    }
    if (parser.flagPresent("--hidden-flag")) {
        std.debug.print("Hidden flag was used!\n", .{});
    }

    std.debug.print("Hello, {s}!\n", .{name});
}
