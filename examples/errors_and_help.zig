const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addFlag("--help", "Show help message");
    try parser.addOption("--name", "World", "Name to greet");
    try parser.addOption("--age", "0", "Age of the person");
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
    const age = parser.getOption("--age") orelse "0";
    std.debug.print("Hello, {s}! You are {s} years old.\n", .{ name, age });
}
