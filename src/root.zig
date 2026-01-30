//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const posix = std.posix;
const c = std.os.linux;

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
pub const stdout = &stdout_writer.interface;

var stdin_buffer: [1024]u8 = undefined;
var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
pub const stdin = &stdin_reader.interface;

pub fn clear() !void {
    try stdout.print("\x1b[2J\x1b[H", .{});
    try stdout.flush();
}

pub fn getTermSize(tty: std.posix.fd_t) !struct { height: u16, width: u16 } {
    var winsz = posix.winsize{
        .col = 0,
        .row = 0,
        .xpixel = 0,
        .ypixel = 0,
    };
    // TIOCGWINSZ is the ioctl command to Get Window SiZe (0x5413 on Linux)
    const TIOCGWINSZ = 0x5413;
    const rv = c.ioctl(tty, TIOCGWINSZ, @intFromPtr(&winsz));

    if (rv == 0) {
        return .{
            .height = winsz.row,
            .width = winsz.col,
        };
    } else {
        return error.FailedToGetTerminalSize;
    }
}

pub const Screen = struct {
    width: u16,
    height: u16,
    out: std.fs.File,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Screen {
        var self = Screen{
            .width = 0,
            .height = 0,
            .out = std.fs.File.stdout(),
            .allocator = allocator,
        };
        try self.updateSize();
        return self;
    }

    pub fn updateSize(self: *Screen) !void {
        // Try to get actual terminal size using ioctl
        if (getTermSize(0)) |size| {
            self.width = size.width;
            self.height = size.height;
        } else |_| {
            // Fallback to environment variables if ioctl fails
            if (std.process.getEnvVarOwned(self.allocator, "COLUMNS")) |cols_str| {
                self.width = @intCast(std.fmt.parseInt(usize, cols_str, 10) catch 80);
                self.allocator.free(cols_str);
            } else |_| {
                self.width = 80;
            }

            if (std.process.getEnvVarOwned(self.allocator, "LINES")) |lines_str| {
                self.height = @intCast(std.fmt.parseInt(usize, lines_str, 10) catch 24);
                self.allocator.free(lines_str);
            } else |_| {
                self.height = 24;
            }
        }
    }

    pub fn checkForResize(self: *Screen) !bool {
        const old_width = self.width;
        const old_height = self.height;
        try self.updateSize();
        return (old_width != self.width or old_height != self.height);
    }

    pub fn drawRows(self: *Screen, user: anytype) !void {
        var y: usize = 0;
        while (y < self.height - 1) : (y += 1) { // Leave space for status bar
            if (user.buffer) |buf| {
                if (buf.getLine(y)) |line| {
                    // Write line content, truncated to terminal width
                    var end_idx = line.len;
                    if (line.len > self.width) {
                        end_idx = self.width;
                    }
                    try self.out.writeAll(line[0..end_idx]);

                    // Fill rest of line with spaces
                    var x: usize = end_idx;
                    while (x < self.width) : (x += 1) {
                        try self.out.writeAll(" ");
                    }
                } else {
                    // Line doesn't exist (end of file), show tilde
                    try self.out.writeAll("~");
                    var x: usize = 1;
                    while (x < self.width) : (x += 1) {
                        try self.out.writeAll(" ");
                    }
                }
            } else {
                // No buffer loaded, show tildes
                try self.out.writeAll("~");
                var x: usize = 1;
                while (x < self.width) : (x += 1) {
                    try self.out.writeAll(" ");
                }
            }

            // Move to next line
            try self.out.writeAll("\r\n");
        }
    }

    pub fn drawCols(self: *Screen) !void {
        var x: usize = 0;
        while (x < self.width) : (x += 1) {
            try self.out.writeAll("|");
        }
    }

    pub fn refresh(self: *Screen, user: anytype) !void {
        // 1. Check for terminal resize
        _ = try self.checkForResize();

        // 2. Hide the cursor while drawing to prevent "ghosting"
        try self.out.writeAll("\x1b[?25l");

        // 3. Move cursor to top-left
        try self.out.writeAll("\x1b[H");

        // 4. Draw the rows of text
        try self.drawRows(user);

        // 5. Draw the status bar at the bottom
        const drawUi = @import("drawUi.zig");
        try drawUi.drawStatusBar(self, user);

        // 6. Move cursor back to user's position
        var buf: [32]u8 = undefined;
        const move_cmd = try std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ user.y + 1, user.x + 1 });
        try self.out.writeAll(move_cmd);

        // 7. Show the cursor again
        try self.out.writeAll("\x1b[?25h");
    }
};

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

pub const Cursor = struct {
    x: usize,
    y: usize,
    visible: bool,

    pub fn init(x: usize, y: usize) Cursor {
        return Cursor{
            .x = x,
            .y = y,
            .visible = true,
        };
    }

    pub fn moveTo(self: *Cursor, x: usize, y: usize) !void {
        self.x = x;
        self.y = y;
        try stdout.print("\x1b[{};{}H", .{ y + 1, x + 1 });
        try stdout.flush();
    }

    pub fn moveRelative(self: *Cursor, dx: i32, dy: i32) !void {
        const new_x = @as(i32, @intCast(self.x)) + dx;
        const new_y = @as(i32, @intCast(self.y)) + dy;

        if (new_x >= 0 and new_y >= 0) {
            const term_size = try getTermSize(0);
            if (new_x < term_size.width and new_y < term_size.height) {
                try self.moveTo(@intCast(new_x), @intCast(new_y));
            }
        }
    }

    pub fn hide(self: *Cursor) !void {
        self.visible = false;
        try stdout.print("\x1b[?25l", .{});
        try stdout.flush();
    }

    pub fn show(self: *Cursor) !void {
        self.visible = true;
        try stdout.print("\x1b[?25h", .{});
        try stdout.flush();
    }

    pub fn save(self: *Cursor) !void {
        _ = self;
        try stdout.print("\x1b[s", .{});
        try stdout.flush();
    }

    pub fn restore(self: *Cursor) !void {
        _ = self;
        try stdout.print("\x1b[u", .{});
        try stdout.flush();
    }
};
