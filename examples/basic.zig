const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addFlag("--help", "Show this help message");
    try parser.addOption("--name", "World", "Name to greet");
    try parser.parse();

    if (parser.flagPresent("--help")) {
        std.debug.print("Usage: --name <name> [--help]\n", .{});
        return;
    }
    const name = parser.getOption("--name") orelse "World";
    std.debug.print("Hello, {s}!\n", .{name});
}
