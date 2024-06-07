const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const hiredis = @cImport({
    @cInclude("hiredis.h");
});
const logz = @import("logz");
const uuid = @import("zul").UUID;
const interface = @import("interface.zig");

pub const DbConnection = union(enum) {
    redis: RedisConnection,
    pub fn connect(self: *DbConnection, host: []const u8, port: u16) !void {
        switch (self.*) {
            inline else => return self.connect(host, port),
        }
    }

    pub fn getUser(self: DbConnection, allocator: Allocator, id: []const u8) !?interface.User {
        switch (self) {
            inline else => |case| return case.getUser(allocator, id),
        }
    }

    pub fn setUser(self: DbConnection, allocator: Allocator, user: interface.User) !void {
        switch (self) {
            inline else => |case| return case.setUser(allocator, user),
        }
    }
};

pub const RedisConnection = struct {
    _conn: [*c]hiredis.struct_redisContext = 0,

    pub const errors = error{
        FailedToConnect,
        FailedToGet,
        FailedToSet,
    };

    pub fn init() RedisConnection {
        return RedisConnection{};
    }

    pub fn deinit(self: RedisConnection) void {
        if (self._conn != 0) {
            hiredis.redisFree(self._conn);
        }
    }

    pub fn connect(self: *RedisConnection, host: [:0]const u8, port: u16) !void {
        if (self._conn == 0) {
            self._conn = hiredis.redisConnect(host, port);
        } else {
            _ = hiredis.redisReconnect(self._conn);
        }
        if (self._conn == null or self._conn.*.err != 0) {
            self.logRedisError();
            return errors.FailedToConnect;
        }
    }

    fn reconnect(self: RedisConnection) void {
        _ = hiredis.redisReconnect(self._conn);
    }

    fn logRedisError(self: RedisConnection) void {
        assert(self._conn != 0);
        logz.err()
            .string("database", "redis")
            .string("errmsg", &self._conn.*.errstr).log();
        if (self._conn.*.err != 0) {
            self.reconnect();
        }
    }

    pub fn getUser(self: RedisConnection, allocator: Allocator, id: []const u8) !?interface.User {
        // ensure string is zero padded
        const user_id = try allocator.dupeZ(u8, id);
        defer allocator.free(user_id);

        const _reply = hiredis.redisCommand(self._conn, "HGETALL user:%s", user_id.ptr) orelse {
            self.logRedisError();
            return errors.FailedToGet;
        };
        const redis_reply: *hiredis.struct_redisReply = @ptrCast(@alignCast(_reply));
        defer hiredis.freeReplyObject(redis_reply);

        if (redis_reply.type != hiredis.REDIS_REPLY_ARRAY or redis_reply.elements == 0) return null;

        var user = interface.User{
            .id = try uuid.parse(id),
            .username = undefined,
        };

        var i: usize = 0;
        std.debug.print("reply.elements = {}\n", .{redis_reply.elements});
        while (i < redis_reply.elements) : (i += 2) {
            const sub_reply: *hiredis.struct_redisReply = @ptrCast(@alignCast(redis_reply.element[i + 1]));
            std.debug.print("sub_reply = {s}\n", .{sub_reply.str[0..sub_reply.len]});
            if (sub_reply.type == hiredis.REDIS_REPLY_STRING and std.mem.eql(u8, "username", sub_reply.str[0..sub_reply.len])) {
                user.username = try allocator.dupe(u8, sub_reply.str[0..sub_reply.len]);
            }
        }

        return user;
    }

    pub fn setUser(self: RedisConnection, allocator: Allocator, user: interface.User) !void {
        // important for the strings to be null terminated
        var id: [37]u8 = undefined;
        @memcpy(id[0..36], &user.id.toHex(.lower));
        id[36] = 0;

        const username = try allocator.dupeZ(u8, user.username);

        _ = hiredis.redisCommand(self._conn, "HSET user:%s username %s", &id, username.ptr) orelse {
            self.logRedisError();
            return errors.FailedToSet;
        };
    }
};
