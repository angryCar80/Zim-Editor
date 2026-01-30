const std = @import("std");

const root = @import("root.zig"); // the core lib for the project
const draw = @import("drawUi.zig");
// Simple Imports
const stdin = root.stdin;
const stdout = root.stdout;
const readKey = root.readKey;
const setRawMode = root.setRawMode;
const Screen = root.Screen;

pub const Mode = enum {
    NOR,
    INS,
    SEL,
    COM,
};
pub const User = struct {
    currentMode: Mode,
    showWelcome: bool,
    pos_x: usize,
    pos_y: usize,

    // USER METHODS
    pub fn moveUp(self: *User) !void {
        _ = self;
        try stdout.print("Move Up\n", .{});
        try stdout.flush();
    }
    pub fn moveDown(self: *User) !void {
        _ = self;
        try stdout.print("Move Down\n", .{});
        try stdout.flush();
    }
    pub fn moveRight(self: *User) !void {
        _ = self;
        try stdout.print("Move Right\n", .{});
        try stdout.flush();
    }
    pub fn moveLeft(self: *User) !void {
        _ = self;
        try stdout.print("Move Left\n", .{});
        try stdout.flush();
    }
};

pub fn main() !void {
    try setRawMode(.on);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var screen = try root.Screen.init(allocator);

    var running: bool = true;
    var user: User = .{ .currentMode = Mode.NOR, .showWelcome = true, .pos_x = 0, .pos_y = 0 };
    while (running) {
        const key = try readKey();
        try draw.drawStatusBar(&screen, user);
        // try screen.out.sync(); WARN Error From This Line!
        if (user.currentMode == Mode.NOR and key == 'q') {
            running = false;
            try setRawMode(.off);
            break;
        } else if (user.currentMode == Mode.NOR and key == 'i') {
            user.currentMode = Mode.INS;
            try screen.refresh(user);
        } else if (user.currentMode == Mode.NOR and key == 'v') {
            user.currentMode = Mode.SEL;
            try screen.refresh(user);
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
                        else => {
                            try screen.refresh(user);
                        },
                    }
                }
            }
        } else {
            continue;
        }
    }
}
