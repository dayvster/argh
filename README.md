# argh

A modern, minimal argument parser for Zig.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![zig 0.15](https://img.shields.io/badge/zig-0.15-f7a41d?logo=zig)](https://ziglang.org/)

---

**argh** is a simple, flexible argument parser for Zig projects. It supports:
- Long and short flags/options (e.g. `--help`, `-h`)
- Positional arguments
- Required arguments
- Mutually exclusive groups
- Helpful error and help messages

## Roadmap

Curious about what's next? See planned and potential features in the [Roadmap](./ROADMAP.md).

## Features

- Simple, declarative API
- Long and short flags/options (e.g. `--help`, `-h`)
- Type-safe int/float options with min/max constraints
- Positional arguments
- Required arguments
- Mutually exclusive groups
- Helpful error and help messages

## Installation

Install with Zig's package manager:

```sh
zig fetch --save git+https://github.com/dayvster/argh
```

Then add to your `build.zig`:

```zig
const argh = b.dependency("argh", .{});
exe.addModule("argh", argh.module("argh"));
```

## Quick Example

```zig
const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addFlagWithShort("--help", "-h", "Show help message");
    try parser.addOptionWithShort("--name", "-n", "World", "Name to greet");
    try parser.addPositional("input", "Input file", true, null);
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
    var input: []const u8 = "(none)";
    if (parser.positionals.items.len > 0 and parser.positionals.items[0].value != null) {
        input = parser.positionals.items[0].value.?;
    }
    std.debug.print("Hello, {s}! Input: {s}\n", .{ name, input });
}
```

## Example: Type-safe int/float options

```zig
const std = @import("std");
const argparse = @import("argh");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = argparse.Parser.init(allocator, args);
    try parser.addIntOption("--count", 5, "How many times", 1, 10);
    try parser.addFloatOption("--ratio", 0.5, "A ratio", 0.0, 1.0);
    try parser.parse();

    const count = try parser.getOptionInt("--count") orelse 5;
    const ratio = try parser.getOptionFloat("--ratio") orelse 0.5;

    std.debug.print("count: {d}\n", .{count});
    std.debug.print("ratio: {:.2}\n", .{ratio});
}
```

## Usage

- **Flags:**
  - `try parser.addFlagWithShort("--help", "-h", "Show help message");`
- **Options:**
  - `try parser.addOptionWithShort("--name", "-n", "World", "Name to greet");`
- **Positional Arguments:**
  - `try parser.addPositional("input", "Input file", true, null);`
- **Required Arguments:**
  - `try parser.setRequired("--name");`
- **Mutually Exclusive Groups:**
  - `try parser.addMutexGroup("group1", &[_][]const u8{ "--foo", "--bar" });`

## Advanced Features

- Short and long flags/options
- Required and default values
- Mutually exclusive argument groups
- Automatic help and error output
- Simple, no-macro API

## Why argh?

- **Minimal:** No macros, no codegen, no dependencies.
- **Clear:** Easy to read, easy to debug.
- **Flexible:** Supports most CLI patterns out of the box.
- **Modern:** Designed for Zig 0.15+.

## Contributing

Pull requests and issues are welcome! Please keep code and documentation clear and minimal.

## License

MIT
