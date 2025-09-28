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

[Planned Features & Roadmap](./PLANNED.md)

## Features

- **Long and Short Flags/Options**: Register both `--flag` and `-f` for the same argument. Supports repeatable flags (e.g. `-v -v`).
- **Options with Default Values**: Options can have default values and help text. Retrieve their value or use the default if not provided.
- **Positional Arguments**: Define required or optional positional arguments (e.g. `myprog input.txt`).
- **Required Arguments**: Mark any flag or option as required. Missing required arguments are reported as errors.
- **Mutually Exclusive Groups**: Define groups of arguments that cannot be used together. The parser reports an error if more than one is present.
- **Automatic Help and Error Output**: Built-in help message generation and clear error reporting for unknown, missing, or conflicting arguments.
- **Simple API**: No macros, no code generation, no dependencies. Just register arguments and call `parse()`.
- **Short and Long Option Aliases**: Use both `-n` and `--name` for the same option.
- **Repeatable Flags**: Count how many times a flag appears (e.g. `-v -v -v`).
- **Modern Zig Style**: Designed for Zig 0.15+, using idiomatic Zig patterns and memory management.
- **MIT Licensed**: Permissive, open source, and ready for any project.

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
