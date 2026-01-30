const std = @import("std");
const main = @import("main.zig");
const root = @import("root.zig");
const Screen = root.Screen;

// pub const status = struct {
//     currentMode: u64,
// };

// pub fn drawStatusBar(writer: anytype, mode: main.Mode, filename: []const u8, cursor_y: usize, cursor_x: usize, screen_width: u16) !void {
//     // 1. Move cursor to the bottom of the screen (last line)
//     // Using ANSI escape: \x1b[H moves to 1,1; we need the bottom!

//     // 2. Format the status string
//     var buf: [256]u8 = undefined;
//     const mode_str = switch (mode) {
//         .NOR => " NORMAL ",
//         .INS => " INSERT ",
//         .SEL => " SELECT ",
//         .COM => " COMMAND ",
//     };

//     const status = try std.fmt.bufPrint(&buf, "{s} | {s} | Line: {}, Col: {}", .{
//         mode_str,
//         filename,
//         cursor_y + 1,
//         cursor_x + 1,
//     });

//     // 3. Write it out (you might add color codes here!)
//     try writer.writeAll("\x1b[7m"); // Invert colors for the bar
//     try writer.writeAll(status);

//     // Fill the rest of the line with spaces
//     var i: usize = status.len;
//     while (i < screen_width) : (i += 1) try writer.writeByte(' ');

//     try writer.writeAll("\x1b[m"); // Reset colors
// }
//
pub fn drawStatusBar(self: *Screen, user: anytype) !void {
    // 1. Move cursor to the last line: self.height
    // Terminals are 1-indexed, so row 1 is the top.
    var buf: [32]u8 = undefined;
    const move_to_bottom = try std.fmt.bufPrint(&buf, "\x1b[{};1H", .{self.height});
    try self.out.writeAll(move_to_bottom);

    // 2. Turn on "Inverted Colors" so the bar looks like a bar
    try self.out.writeAll("\x1b[7m");

    // 3. Build your status string
    var status_buf: [256]u8 = undefined;
    const status_text = try std.fmt.bufPrint(&status_buf, " ZIM | {s} | Line: {} | Col: {} ", .{
        @tagName(user.currentMode),
        user.pos_y + 1,
        user.pos_x + 1,
    });
    try self.out.writeAll(status_text);

    // 4. Fill the rest of the width with spaces so the bar goes across the whole screen
    var i: usize = status_text.len;
    while (i < self.width) : (i += 1) {
        try self.out.writeAll(" ");
    }

    // 5. Turn off inverted colors (reset to normal)
    try self.out.writeAll("\x1b[m");
}
