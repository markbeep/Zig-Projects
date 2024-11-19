const std = @import("std");
const Node = @import("node.zig").Node;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const node = Node.init();
    try node.listen(gpa.allocator(), "0.0.0.0", 9601);
}

test {
    _ = Node.init(); // Includes the tests for Node
}
