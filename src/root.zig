//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
pub const stdout = &stdout_writer.interface;

var stdin_buffer: [1024]u8 = undefined;
var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
pub const stdin = &stdin_reader.interface;

pub const Screen = struct {
    width: u16,
    height: u16,
    out: std.fs.File,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Screen {
        var self = Screen{
            .width = 0,
            .height = 0,
            .out = std.io.getStdOut(),
            .allocator = allocator,
        };
        try self.updateSize();
        return self;
    }

    pub fn updateSize(self: *Screen) !void {
        _ = self;
        // Here you'd use your getTerminalSize implementation
        // For example, using ioctl on Linux/macOS
        // self.width = ...
        // self.height = ...
    }

    pub fn refresh(self: *Screen, user: anytype) !void {
        // 1. Hide the cursor while drawing to prevent "ghosting"
        try self.out.writeAll("\x1b[?25l");

        // 2. Move cursor to top-left
        try self.out.writeAll("\x1b[H");

        // 3. Draw the rows of text
        try self.drawRows();

        // 4. Draw the status bar at the bottom
        try self.drawStatusBar(user);

        // 5. Move cursor back to user's position
        var buf: [32]u8 = undefined;
        const move_cmd = try std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ user.y + 1, user.x + 1 });
        try self.out.writeAll(move_cmd);

        // 6. Show the cursor again
        try self.out.writeAll("\x1b[?25h");
    }
};
// Get terminal dimensions with fallback
pub fn getTerminalSize() Screen {
    var screen = Screen{ .cols = 80, .rows = 24 };

    // Try to get size from environment variables
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "COLUMNS")) |cols_str| {
        screen.cols = std.fmt.parseInt(usize, cols_str, 10) catch screen.cols;
        std.heap.page_allocator.free(cols_str);
    } else |_| {}

    if (std.process.getEnvVarOwned(std.heap.page_allocator, "LINES")) |lines_str| {
        screen.rows = std.fmt.parseInt(usize, lines_str, 10) catch screen.rows;
        std.heap.page_allocator.free(lines_str);
    } else |_| {}

    return screen;
}

pub fn setRawMode(state: enum(u1) { on, off }) !void {
    var termios = try std.posix.tcgetattr(0);
    termios.lflag.ECHO = state != .on;
    termios.lflag.ICANON = state != .on;
    try std.posix.tcsetattr(0, .FLUSH, termios);
}

pub fn readKey() !u8 {
    const bytes_read = try stdin.takeByte();
    if (bytes_read == 0) return error.EndOfFile;
    return bytes_read;
}
