const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addFlag("-v", "Increase verbosity");
    try parser.addFlag("--help", "Show help message");
    try parser.parse();

    if (parser.flagPresent("--help")) {
        parser.printHelp();
        return;
    }
    const verbosity = parser.flagCount("-v");
    std.debug.print("Verbosity level: {d}\n", .{verbosity});
}
