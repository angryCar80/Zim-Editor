const std = @import("std");
const fs = std.fs;

const root = @import("root.zig");
const stdout = root.stdout;
const stdin = root.stdin;

pub const Buffer = struct {
    content: []u8,
    lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    file_path: []const u8,
    is_binary: bool,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Buffer {
        var buffer = Buffer{
            .content = "",
            .lines = try std.ArrayList([]const u8).initCapacity(allocator, 0),
            .allocator = allocator,
            .file_path = try allocator.dupe(u8, file_path),
            .is_binary = false,
        };

        try buffer.loadFromFile();
        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.content);
        self.allocator.free(self.file_path);

        // Free all line slices
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
    }

    fn loadFromFile(self: *Buffer) !void {
        const cwd = fs.cwd();

        // Try to open file, create empty if doesn't exist like vim/helix
        const file = cwd.openFile(self.file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Create empty file
                const new_file = try cwd.createFile(self.file_path, .{});
                new_file.close();
                self.content = "";
                try self.splitIntoLines();
                return;
            },
            else => return err,
        };
        defer file.close();

        // Get file size for dynamic allocation
        const file_size = try file.getEndPos();

        // Handle empty file
        if (file_size == 0) {
            self.content = "";
            try self.splitIntoLines();
            return;
        }

        // Allocate exact size needed (memory optimization)
        self.content = try self.allocator.alloc(u8, file_size);

        // Read entire file (faster for small-medium files)
        const bytes_read = try file.readAll(self.content);

        // Validate complete read
        if (bytes_read != file_size) {
            self.allocator.free(self.content);
            return error.IncompleteRead;
        }

        // Check for binary content
        self.is_binary = self.isBinaryContent();

        if (self.is_binary) {
            return error.BinaryFile;
        }

        // Split into lines for efficient rendering
        try self.splitIntoLines();
    }

    fn isBinaryContent(self: Buffer) bool {
        // Check for null bytes and control characters
        for (self.content) |byte| {
            if (byte == 0) return true; // Null byte = binary
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

        // Add last line if no trailing newline
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
        const cwd = fs.cwd();
        const file = try cwd.createFile(self.file_path, .{});
        defer file.close();

        try file.writeAll(self.content);
    }

    pub fn insertChar(self: *Buffer, line_num: usize, col: usize, char: u8) !void {
        if (line_num >= self.lines.items.len) return;

        const old_line = self.lines.items[line_num];
        const new_len = old_line.len + 1;
        const new_line = try self.allocator.alloc(u8, new_len);

        // Copy before insertion point
        @memcpy(new_line[0..col], old_line[0..col]);
        // Insert character
        new_line[col] = char;
        // Copy after insertion point
        if (col < old_line.len) {
            @memcpy(new_line[col + 1 ..], old_line[col..]);
        }

        // Free old line and update
        self.allocator.free(old_line);
        self.lines.items[line_num] = new_line;

        // Update content
        try self.rebuildContent();
    }

    pub fn insertNewLine(self: *Buffer, line_num: usize, col: usize) !void {
        if (line_num >= self.lines.items.len) return;

        const old_line = self.lines.items[line_num];
        const new_line_len = old_line.len - col;

        // Create new line with content after cursor
        const new_line = try self.allocator.alloc(u8, new_line_len);
        if (new_line_len > 0) {
            @memcpy(new_line, old_line[col..]);
        }

        // Truncate old line
        const truncated_line = try self.allocator.alloc(u8, col);
        @memcpy(truncated_line, old_line[0..col]);

        self.allocator.free(old_line);
        self.lines.items[line_num] = truncated_line;

        // Insert new line after current
        try self.lines.insert(self.allocator, line_num + 1, new_line);

        // Update content
        try self.rebuildContent();
    }

    pub fn insertEmptyLineBelow(self: *Buffer, line_num: usize) !void {
        // Insert an empty line after the specified line
        const empty_line = try self.allocator.alloc(u8, 0);
        try self.lines.insert(self.allocator, line_num + 1, empty_line);
        try self.rebuildContent();
    }

    fn rebuildContent(self: *Buffer) !void {
        // Calculate total size needed
        var total_size: usize = 0;
        for (self.lines.items) |line| {
            total_size += line.len + 1; // +1 for newline
        }

        // Free old content and allocate new
        if (self.content.len > 0) {
            self.allocator.free(self.content);
        }
        self.content = try self.allocator.alloc(u8, total_size);

        // Build content
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
};

pub fn loadFile(allocator: std.mem.Allocator, file_path: []const u8) !Buffer {
    return Buffer.init(allocator, file_path);
}

pub fn createEmptyFile(allocator: std.mem.Allocator, file_path: []const u8) !Buffer {
    const buffer = Buffer{
        .content = "",
        .lines = try std.ArrayList([]const u8).initCapacity(allocator, 0),
        .allocator = allocator,
        .file_path = try allocator.dupe(u8, file_path),
        .is_binary = false,
    };

    // Create empty file on disk
    const cwd = fs.cwd();
    const file = try cwd.createFile(file_path, .{});
    file.close();

    return buffer;
}

// Legacy function - use loadFile instead
pub fn readFile() !void {
    const cwd = fs.cwd();
    const open_file_flags = fs.File.OpenFlags{ .mode = .read_only };
    const file_path = "src/test.txt";

    const file = try cwd.openFile(file_path, open_file_flags);

    const buffer = try std.heap.page_allocator.alloc(u8, 1024);
    defer std.heap.page_allocator.free(buffer);

    const bytes_read = try file.read(buffer);

    try stdout.print("{s}\n", .{buffer[0..bytes_read]});
    try stdout.flush();
}
