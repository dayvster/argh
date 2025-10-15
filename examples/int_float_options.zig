const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addIntOption("--count", null, 5, "How many times", 1, 10);
    try parser.addFloatOption("--ratio", null, 0.5, "A ratio", 0.0, 1.0);
    try parser.parse();

    const count = try parser.getOptionInt("--count") orelse 5;
    const ratio = try parser.getOptionFloat("--ratio") orelse 0.5;

    std.debug.print("count: {d}\n", .{count});
    std.debug.print("ratio: {:.2}\n", .{ratio});
}
