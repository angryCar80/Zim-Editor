const std = @import("std");
const main = @import("main.zig");

// pub const status = struct {
//     currentMode: u64,
// };

pub fn drawStatusBar(writer: anytype, mode: main.Mode, filename: []const u8, cursor_y: usize, cursor_x: usize, screen_width: u16) !void {
    // 1. Move cursor to the bottom of the screen (last line)
    // Using ANSI escape: \x1b[H moves to 1,1; we need the bottom!

    // 2. Format the status string
    var buf: [256]u8 = undefined;
    const mode_str = switch (mode) {
        .NOR => " NORMAL ",
        .INS => " INSERT ",
        .SEL => " SELECT ",
        .COM => " COMMAND ",
    };

    const status = try std.fmt.bufPrint(&buf, "{s} | {s} | Line: {}, Col: {}", .{
        mode_str,
        filename,
        cursor_y + 1,
        cursor_x + 1,
    });

    // 3. Write it out (you might add color codes here!)
    try writer.writeAll("\x1b[7m"); // Invert colors for the bar
    try writer.writeAll(status);

    // Fill the rest of the line with spaces
    var i: usize = status.len;
    while (i < screen_width) : (i += 1) try writer.writeByte(' ');

    try writer.writeAll("\x1b[m"); // Reset colors
}
