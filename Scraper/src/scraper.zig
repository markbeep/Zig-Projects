const std = @import("std");
const testing = std.testing;

const ScraperError = error{
    InvalidStatus,
};

pub fn testRequest(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const result = try client.fetch(.{
        .method = .GET,
        .location = .{ .uri = uri },
        .response_storage = .{ .dynamic = &buffer },
    });
    if (@intFromEnum(result.status) >= 200 and @intFromEnum(result.status) < 300) {
        return try buffer.toOwnedSlice();
    }

    return ScraperError.InvalidStatus;
}
