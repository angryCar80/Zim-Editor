const std = @import("std");
const Io = std.Io;

pub const Buffer = struct {
    content: []u8,
    lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    is_binary: bool,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Buffer {
        var buffer = Buffer{
            .content = "",
            .lines = try std.ArrayList([]const u8).initCapacity(allocator, 0),
            .allocator = allocator,
            .io = io,
            .file_path = try allocator.dupe(u8, file_path),
            .is_binary = false,
        };

        try buffer.loadFromFile();
        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.content);
        self.allocator.free(self.file_path);

        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
    }

    fn loadFromFile(self: *Buffer) !void {
        const cwd = Io.Dir.cwd();

        const file = cwd.openFile(self.io, self.file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                const new_file = try cwd.createFile(self.io, self.file_path, .{});
                new_file.close(self.io);
                self.content = "";
                try self.splitIntoLines();
                return;
            },
            else => return err,
        };
        defer file.close(self.io);

        const file_size = try file.length(self.io);

        if (file_size == 0) {
            self.content = "";
            try self.splitIntoLines();
            return;
        }

        self.content = try self.allocator.alloc(u8, file_size);

        var total_read: usize = 0;
        while (total_read < file_size) {
            const iov = [_][]u8{self.content[total_read..]};
            total_read += try file.readStreaming(self.io, &iov);
        }

        self.is_binary = self.isBinaryContent();

        if (self.is_binary) {
            return error.BinaryFile;
        }

        try self.splitIntoLines();
    }

    fn isBinaryContent(self: Buffer) bool {
        for (self.content) |byte| {
            if (byte == 0) return true;
            if (byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') return true;
        }
        return false;
    }

    fn splitIntoLines(self: *Buffer) !void {
        var start: usize = 0;

        for (self.content, 0..) |byte, i| {
            if (byte == '\n') {
                const line_len = i - start;
                const line = try self.allocator.alloc(u8, line_len);
                @memcpy(line, self.content[start..i]);
                try self.lines.append(self.allocator, line);
                start = i + 1;
            }
        }

        if (start < self.content.len) {
            const line_len = self.content.len - start;
            const line = try self.allocator.alloc(u8, line_len);
            @memcpy(line, self.content[start..]);
            try self.lines.append(self.allocator, line);
        }
    }

    pub fn getLine(self: Buffer, line_num: usize) ?[]const u8 {
        if (line_num >= self.lines.items.len) return null;
        return self.lines.items[line_num];
    }

    pub fn getLineCount(self: Buffer) usize {
        return self.lines.items.len;
    }

    pub fn saveToFile(self: Buffer) !void {
        const cwd = Io.Dir.cwd();
        const file = try cwd.createFile(self.io, self.file_path, .{});
        defer file.close(self.io);

        try file.writeStreamingAll(self.io, self.content);
    }

    pub fn insertChar(self: *Buffer, line_num: usize, col: usize, char: u8) !void {
        if (line_num >= self.lines.items.len) return;

        const old_line = self.lines.items[line_num];
        const new_len = old_line.len + 1;
        const new_line = try self.allocator.alloc(u8, new_len);

        @memcpy(new_line[0..col], old_line[0..col]);
        new_line[col] = char;
        if (col < old_line.len) {
            @memcpy(new_line[col + 1 ..], old_line[col..]);
        }

        self.allocator.free(old_line);
        self.lines.items[line_num] = new_line;

        try self.rebuildContent();
    }

    pub fn insertNewLine(self: *Buffer, line_num: usize, col: usize) !void {
        if (line_num >= self.lines.items.len) return;

        const old_line = self.lines.items[line_num];
        const new_line_len = old_line.len - col;

        const new_line = try self.allocator.alloc(u8, new_line_len);
        if (new_line_len > 0) {
            @memcpy(new_line, old_line[col..]);
        }

        const truncated_line = try self.allocator.alloc(u8, col);
        @memcpy(truncated_line, old_line[0..col]);

        self.allocator.free(old_line);
        self.lines.items[line_num] = truncated_line;

        try self.lines.insert(self.allocator, line_num + 1, new_line);

        try self.rebuildContent();
    }

    pub fn insertEmptyLineBelow(self: *Buffer, line_num: usize) !void {
        const empty_line = try self.allocator.alloc(u8, 0);
        try self.lines.insert(self.allocator, line_num + 1, empty_line);
        try self.rebuildContent();
    }

    pub fn replaceChar(self: *Buffer, line_num: usize, col: usize, ch: u8) !void {
        if (line_num >= self.lines.items.len) return;

        const old_line = self.lines.items[line_num];

        if (col >= old_line.len) {
            try self.insertChar(line_num, col, ch);
            return;
        }

        const new_line = try self.allocator.alloc(u8, old_line.len);
        @memcpy(new_line, old_line);
        new_line[col] = ch;

        self.allocator.free(old_line);
        self.lines.items[line_num] = new_line;

        try self.rebuildContent();
    }

    fn rebuildContent(self: *Buffer) !void {
        var total_size: usize = 0;
        for (self.lines.items) |line| {
            total_size += line.len + 1;
        }

        if (self.content.len > 0) {
            self.allocator.free(self.content);
        }
        self.content = try self.allocator.alloc(u8, total_size);

        var pos: usize = 0;
        for (self.lines.items) |line| {
            @memcpy(self.content[pos .. pos + line.len], line);
            pos += line.len;
            if (pos < total_size) {
                self.content[pos] = '\n';
                pos += 1;
            }
        }
    }

    pub fn removeChar(self: *Buffer, line_num: usize, col: usize) !bool {
        if (line_num >= self.lines.items.len) return false;

        const old_line = self.lines.items[line_num];

        if (col >= old_line.len) return false;

        const new_len = old_line.len - 1;
        if (new_len == 0) {
            self.allocator.free(old_line);
            _ = self.lines.orderedRemove(line_num);
            try self.rebuildContent();
            return true;
        }

        const new_line = try self.allocator.alloc(u8, new_len);
        @memcpy(new_line[0..col], old_line[0..col]);
        @memcpy(new_line[col..], old_line[col + 1 ..]);

        self.allocator.free(old_line);
        self.lines.items[line_num] = new_line;
        try self.rebuildContent();
        return false;
    }
};

pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Buffer {
    return Buffer.init(allocator, io, file_path);
}
