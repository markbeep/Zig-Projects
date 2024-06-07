const uuid = @import("zul").UUID;

pub const User = struct {
    id: uuid,
    username: []const u8,
};

pub const UnserializedUser = struct {
    id: []const u8,
    username: []const u8,
};

pub const CreateUserRequest = struct {
    username: []const u8,
};
