const std = @import("std");
const linux = std.os.linux;

pub fn clear(io: std.Io) !void {
    try std.Io.File.stdout().writeStreamingAll(io, "\x1b[2J\x1b[H");
}

pub fn getTermSize(tty: std.posix.fd_t) !struct { height: u16, width: u16 } {
    var winsz = std.posix.winsize{
        .col = 0,
        .row = 0,
        .xpixel = 0,
        .ypixel = 0,
    };
    const TIOCGWINSZ = 0x5413;
    const rv = linux.ioctl(tty, TIOCGWINSZ, @intFromPtr(&winsz));

    if (rv == 0) {
        return .{
            .height = winsz.row,
            .width = winsz.col,
        };
    } else {
        return error.FailedToGetTerminalSize;
    }
}

pub fn formatWrite(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, fmt, args);
    try std.Io.File.stdout().writeStreamingAll(io, formatted);
}

pub const Screen = struct {
    width: u16,
    height: u16,
    io: std.Io,
    stdout_file: std.Io.File,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Screen {
        var self = Screen{
            .width = 0,
            .height = 0,
            .io = io,
            .stdout_file = std.Io.File.stdout(),
            .allocator = allocator,
        };
        try self.updateSize();
        return self;
    }

    pub fn updateSize(self: *Screen) !void {
        if (getTermSize(0)) |size| {
            self.width = size.width;
            self.height = size.height;
        } else |_| {
            self.width = 80;
            self.height = 24;
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
        while (y < self.height - 1) : (y += 1) {
            if (user.buffer) |buf| {
                if (buf.getLine(y)) |line| {
                    var end_idx = line.len;
                    if (line.len > self.width) {
                        end_idx = self.width;
                    }
                    try self.stdout_file.writeStreamingAll(self.io, line[0..end_idx]);

                    var x: usize = end_idx;
                    while (x < self.width) : (x += 1) {
                        try self.stdout_file.writeStreamingAll(self.io, " ");
                    }
                } else {
                    try self.stdout_file.writeStreamingAll(self.io, "~");
                    var x: usize = 1;
                    while (x < self.width) : (x += 1) {
                        try self.stdout_file.writeStreamingAll(self.io, " ");
                    }
                }
            } else {
                try self.stdout_file.writeStreamingAll(self.io, "~");
                var x: usize = 1;
                while (x < self.width) : (x += 1) {
                    try self.stdout_file.writeStreamingAll(self.io, " ");
                }
            }

            try self.stdout_file.writeStreamingAll(self.io, "\r\n");
        }
    }

    pub fn refresh(self: *Screen, user: anytype) !void {
        _ = try self.checkForResize();

        try self.stdout_file.writeStreamingAll(self.io, "\x1b[?25l");
        try self.stdout_file.writeStreamingAll(self.io, "\x1b[H");
        try self.drawRows(user);

        const drawUi = @import("drawUi.zig");
        try drawUi.drawStatusBar(self, user);

        const cursor_y = @min(user.y + 1, self.height - 1);
        const cursor_x = @min(user.x + 1, self.width - 1);

        var buf: [32]u8 = undefined;
        const move_cmd = try std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ cursor_y, cursor_x });
        try self.stdout_file.writeStreamingAll(self.io, move_cmd);

        try self.stdout_file.writeStreamingAll(self.io, "\x1b[?25h");
    }
};

pub fn setRawMode(state: enum(u1) { on, off }) !void {
    var termios: linux.termios = undefined;
    if (linux.tcgetattr(0, &termios) != 0) return error.FailedToSetRawMode;
    termios.lflag.ECHO = state != .on;
    termios.lflag.ICANON = state != .on;
    if (linux.tcsetattr(0, .FLUSH, &termios) != 0) return error.FailedToSetRawMode;
}

pub fn readKey(io: std.Io) !u8 {
    var buf: [1]u8 = undefined;
    const iov = [_][]u8{buf[0..]};
    const nread = try std.Io.File.stdin().readStreaming(io, &iov);
    if (nread == 0) return error.EndOfFile;
    return buf[0];
}
