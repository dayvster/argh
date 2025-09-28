const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addPositionalWithCount("input", "Input files", 2, 3);
    try parser.parse();

    if (parser.errors.items.len > 0) {
        parser.printErrors();
        parser.printHelp();
        return;
    }

    std.debug.print("Inputs provided:\n", .{});
    for (parser.positionals.items) |pos| {
        if (pos.value) |val| std.debug.print("  {s}\n", .{val});
    }
}
