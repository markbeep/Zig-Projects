const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Node = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    fn listenOnConnection(_: Self, allocator: Allocator, server: *std.net.Server) !void {
        var client = try server.accept();
        const reader = client.stream.reader();
        const writer = client.stream.writer();
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        std.log.info("New connection: {}", .{client.address});
        while (true) {
            const packet = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 65536) orelse break;
            defer allocator.free(packet);

            std.log.debug("Packet: {s}", .{packet});

            try std.fmt.format(buffer.writer(), "Received {} bytes\n", .{packet.len});
            defer buffer.clearAndFree();
            try writer.writeAll(buffer.items);
        }
        std.log.warn("Closed connection: {}", .{client.address});
    }

    pub fn listen(self: Self, allocator: Allocator, host: []const u8, port: u16) !void {
        const addr = try std.net.Address.parseIp(host, port);
        var server = try addr.listen(.{});
        defer server.deinit();

        std.log.info("Listening on {s}:{}", .{ host, port });

        while (true) {
            try self.listenOnConnection(allocator, &server);
        }
    }
};

test "set ips" {
    const allocator = std.testing.allocator;
    const node = Node.init();
    try node.listen(allocator, "0.0.0.0", 9600);
    try node.listen(allocator, "::1", 9600);
}
