const std = @import("std");
const main = @import("main.zig");
const root = @import("root.zig");
const Screen = root.Screen;

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
        user.y + 1,
        user.x + 1,
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
