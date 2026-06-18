const std = @import("std");
const root = @import("root.zig");
const Screen = root.Screen;

pub fn drawStatusBar(self: *Screen, user: anytype) !void {
    var buf: [32]u8 = undefined;
    const move_to_bottom = try std.fmt.bufPrint(&buf, "\x1b[{};1H", .{self.height});
    try self.stdout_file.writeStreamingAll(self.io, move_to_bottom);

    try self.stdout_file.writeStreamingAll(self.io, "\x1b[7m");

    var status_buf: [256]u8 = undefined;
    const status_text = try std.fmt.bufPrint(&status_buf, " ZIM | {s} | Line: {} | Col: {} ", .{
        @tagName(user.currentMode),
        user.y + 1,
        user.x + 1,
    });
    try self.stdout_file.writeStreamingAll(self.io, status_text);

    var i: usize = status_text.len;
    while (i < self.width) : (i += 1) {
        try self.stdout_file.writeStreamingAll(self.io, " ");
    }

    try self.stdout_file.writeStreamingAll(self.io, "\x1b[m");
}
