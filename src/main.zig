const std = @import("std");

const root = @import("root.zig"); // the core lib for the project
const draw = @import("drawUi.zig");
const file = @import("files.zig");
// Simple Imports
const stdin = root.stdin;
const stdout = root.stdout;
const readKey = root.readKey;
const setRawMode = root.setRawMode;
const clear = root.clear;
const Screen = root.Screen;
const Cursor = root.Cursor;

pub const Mode = enum {
    NOR,
    INS,
    SEL,
    COM,
};

pub const User = struct {
    currentMode: Mode,
    showWelcome: bool,
    x: usize,
    y: usize,
    buffer: ?file.Buffer,

    pub fn init() User {
        return User{
            .currentMode = Mode.NOR,
            .showWelcome = false,
            .x = 0,
            .y = 0,
            .buffer = null,
        };
    }

    pub fn deinit(self: *User) void {
        if (self.buffer) |*buf| {
            buf.deinit();
        }
    }

    pub fn openFile(self: *User, allocator: std.mem.Allocator, file_path: []const u8) !void {
        if (self.buffer) |*buf| {
            buf.deinit();
        }

        self.buffer = file.loadFile(allocator, file_path) catch |err| switch (err) {
            error.BinaryFile => {
                try stdout.print("Error: Cannot open binary file '{s}'\n", .{file_path});
                try stdout.flush();
                return;
            },
            else => {
                try stdout.print("Error loading file '{s}': {}\n", .{ file_path, err });
                try stdout.flush();
                return;
            },
        };

        self.x = 0;
        self.y = 0;
    }

    // USER METHODS
    pub fn moveUp(self: *User) !void {
        if (self.y > 0) {
            self.y -= 1;
        }
    }
    pub fn moveDown(self: *User) !void {
        if (self.buffer) |buf| {
            if (self.y < buf.getLineCount() - 1) {
                self.y += 1;
            }
        }
    }
    pub fn moveRight(self: *User) !void {
        if (self.buffer) |buf| {
            if (buf.getLine(self.y)) |line| {
                if (self.x < line.len) {
                    self.x += 1;
                }
            }
        }
    }
    pub fn moveLeft(self: *User) !void {
        if (self.x > 0) {
            self.x -= 1;
        }
    }
};

const term_size = root.getTermSize(0);

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    try clear();
    try setRawMode(.on);
    try stdout.flush();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var screen = try root.Screen.init(allocator);

    var user = User.init();
    defer user.deinit();

    // Load file from command line argument or default to test.txt
    if (args.len > 1) {
        try user.openFile(allocator, args[1]);
    } else {
        try user.openFile(allocator, "src/test.txt");
    }

    var cursor = Cursor.init(user.x, user.y);
    try cursor.hide();
    defer {
        cursor.show() catch {};
    }

    var running: bool = true;
    while (running) {
        try stdout.flush();
        const key = try readKey();

        try screen.refresh(user);
        try draw.drawStatusBar(&screen, user);

        if (user.currentMode == Mode.NOR and key == 'q') {
            running = false;
            try setRawMode(.off);
            break;
        } else if (user.currentMode == Mode.NOR and key == 'i') {
            user.currentMode = Mode.INS;
        } else if (user.currentMode == Mode.NOR and key == 'v') {
            user.currentMode = Mode.SEL;
        } else if (user.currentMode == Mode.NOR and key == 'o') {
            user.currentMode = Mode.COM;
        } else if (user.currentMode == Mode.COM and key == '\n') {
            user.currentMode = .NOR;
        }

        if (key == '\x1b') {
            // We got an ESC byte. Now, is there more data waiting?
            // We use a small timeout to see if '[' follows immediately (Arrow keys)
            var poll_fds = [_]std.os.linux.pollfd{.{
                .fd = std.fs.File.stdin().handle,
                .events = std.os.linux.POLL.IN,
                .revents = 0,
            }};

            // Wait for 0 milliseconds (instant check)
            const ready = std.os.linux.poll(&poll_fds, 0, 1);

            if (ready == 0) {
                // No more bytes waiting? This was a real ESC key press!
                user.currentMode = .NOR;
            } else {
                // More bytes are waiting! It's likely an arrow key sequence.
                const second_byte = try readKey();
                if (second_byte == '[') {
                    const third_byte = try readKey();
                    switch (third_byte) {
                        'A' => try user.moveUp(),
                        'B' => try user.moveDown(),
                        'C' => try user.moveRight(),
                        'D' => try user.moveLeft(),
                        else => {},
                    }
                }
            }
        }
    }
}
