pub const Parser = @import("argparse.zig").Parser;
pub const ParseError = @import("argparse.zig").ParseError;
pub const OptionType = @import("argparse.zig").OptionType;
pub const FlagInfo = @import("argparse.zig").FlagInfo;
pub const OptionInfo = @import("argparse.zig").OptionInfo;
pub const PositionalInfo = @import("argparse.zig").PositionalInfo;
pub const MutexGroup = @import("argparse.zig").MutexGroup;
pub const HelpStyle = @import("argparse.zig").HelpStyle;
pub const utils = @import("utils/utils.zig");

test "root includes all types" {
    const P = Parser;
    const PE = ParseError;
    const OT = OptionType;
    const FI = FlagInfo;
    const OI = OptionInfo;
    const PI = PositionalInfo;
    const MG = MutexGroup;
    const HS = HelpStyle;
    _ = .{ P, PE, OT, FI, OI, PI, MG, HS };
}

test {
    _ = @import("tests/parser_test.zig");
}
