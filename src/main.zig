const std = @import("std");

const root = @import("root.zig");
const draw = @import("drawUi.zig");
const file = @import("files.zig");
const readKey = root.readKey;
const setRawMode = root.setRawMode;
const clear = root.clear;
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

    pub fn openFile(self: *User, allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !void {
        if (self.buffer) |*buf| {
            buf.deinit();
        }

        self.buffer = file.Buffer.init(allocator, io, file_path) catch |err| switch (err) {
            error.BinaryFile => {
                try root.formatWrite(io, "Error: Cannot open binary file '{s}'\n", .{file_path});
                return;
            },
            else => {
                try root.formatWrite(io, "Error loading file '{s}': {}\n", .{ file_path, err });
                return;
            },
        };

        self.x = 0;
        self.y = 0;
    }

    pub fn moveUp(self: *User) void {
        if (self.y > 0) {
            self.y -= 1;
            if (self.buffer) |buf| {
                if (buf.getLine(self.y)) |line| {
                    if (self.x > line.len) {
                        self.x = line.len;
                    }
                }
            }
        }
    }
    pub fn moveDown(self: *User) void {
        if (self.buffer) |buf| {
            if (self.y < buf.getLineCount() - 1) {
                self.y += 1;
                if (buf.getLine(self.y)) |line| {
                    if (self.x > line.len) {
                        self.x = line.len;
                    }
                }
            }
        }
    }
    pub fn moveRight(self: *User) void {
        if (self.buffer) |buf| {
            if (buf.getLine(self.y)) |line| {
                if (self.x < line.len) {
                    self.x += 1;
                } else if (self.x == line.len and self.y < buf.getLineCount() - 1) {
                    self.y += 1;
                    self.x = 0;
                }
            }
        }
    }
    pub fn moveLeft(self: *User) void {
        if (self.x > 0) {
            self.x -= 1;
        } else if (self.y > 0) {
            if (self.buffer) |buf| {
                if (buf.getLine(self.y - 1)) |line| {
                    self.y -= 1;
                    self.x = line.len;
                }
            }
        }
    }

    pub fn moveToStart(self: *User) void {
        self.x = 0;
        self.y = 0;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    try clear(io);
    try setRawMode(.on);

    var screen = try root.Screen.init(gpa, io);

    var user = User.init();
    defer user.deinit();

    if (args.len > 1) {
        try user.openFile(gpa, io, args[1]);
        user.moveToStart();
    } else {
        try user.openFile(gpa, io, "src/test.txt");
    }

    try screen.refresh(user);

    var running: bool = true;
    while (running) {
        const key = try readKey(io);

        if (user.currentMode == Mode.NOR and key == 'q') {
            running = false;
            try setRawMode(.off);
            try clear(io);
            break;
        } else if (user.currentMode == Mode.NOR and key == 'i') {
            user.currentMode = Mode.INS;
            continue;
        } else if (user.currentMode == Mode.NOR and key == 'v') {
            user.currentMode = Mode.SEL;
        } else if (user.currentMode == Mode.NOR and key == ':') {
            user.currentMode = Mode.COM;
        } else if (user.currentMode == Mode.COM and key == '\n') {
            user.currentMode = .NOR;
        } else if (user.currentMode == Mode.INS and key == '\x7f') {}

        if (user.currentMode == Mode.NOR and key == 'o') {
            try screen.refresh(user);
            if (user.buffer) |*buf| {
                try buf.insertEmptyLineBelow(user.y);
                user.y += 1;
                user.x = 0;
                user.currentMode = Mode.INS;
                try screen.refresh(user);
                continue;
            }
        } else if (user.currentMode == Mode.NOR and key == 'a') {
            try screen.refresh(user);
            user.currentMode = Mode.INS;
            user.moveRight();
            continue;
        }
        if (key == '\x1b') {
            var poll_fds = [_]std.os.linux.pollfd{.{
                .fd = 0,
                .events = std.os.linux.POLL.IN,
                .revents = 0,
            }};

            const ready = std.os.linux.poll(&poll_fds, 0, 1);

            if (ready == 0) {
                user.currentMode = .NOR;
            } else {
                const second_byte = try readKey(io);
                if (second_byte == '[') {
                    const third_byte = try readKey(io);
                    switch (third_byte) {
                        'A' => user.moveUp(),
                        'B' => user.moveDown(),
                        'C' => user.moveRight(),
                        'D' => user.moveLeft(),
                        else => {},
                    }
                }
            }
        } else if (user.currentMode == .NOR and key == 'j') {
            user.moveDown();
        } else if (user.currentMode == .NOR and key == 'k') {
            user.moveUp();
        } else if (user.currentMode == .NOR and key == 'h') {
            user.moveLeft();
        } else if (user.currentMode == .NOR and key == 'l') {
            user.moveRight();
        } else if (user.currentMode == .NOR and key == 'r') {} else if (user.currentMode == .NOR and key == 'x') {
            if (user.buffer) |*buf| {
                const line_removed = try buf.removeChar(user.y, user.x);
                if (line_removed and user.y > 0) {
                    user.y -= 1;
                }
            }
        }

        if (user.currentMode == .INS) {
            if (key == 127 or key == 8) {} else if (key == '\r' or key == '\n') {
                if (user.buffer) |*buf| {
                    try buf.insertNewLine(user.y, user.x);
                    user.y += 1;
                    user.x = 0;
                }
            } else if (key >= 32 and key < 127) {
                if (user.buffer) |*buf| {
                    try buf.insertChar(user.y, user.x, key);
                    user.x += 1;
                }
            }
        }

        try screen.refresh(user);
    }
}
