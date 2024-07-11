const std = @import("std");
const s = @import("scraper.zig");
const t = @cImport({
    @cInclude("tidy.h");
    @cInclude("tidybuffio.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const blog = try s.testRequest(allocator, "https://markc.su");

    std.debug.print("Res = {s}\n", .{blog});

    var buffer = t.TidyBuffer{};
    var errBuffer = t.TidyBuffer{};

    const tdoc = t.tidyCreate();
    const blogZ = try allocator.dupeZ(u8, blog);

    _ = t.tidySetErrorBuffer(tdoc, &errBuffer);

    const rc = t.tidyParseString(tdoc, blogZ);
    if (rc < 0) {
        return std.debug.print("Failed to parse\n", .{});
    }
    _ = t.tidySaveBuffer(tdoc, &buffer);
    std.debug.print("RC = {}\n", .{rc});

    defer t.tidyBufFree(&buffer);
    defer t.tidyBufFree(&errBuffer);

    const errOuput = std.mem.span(errBuffer.bp);
    std.debug.print("ERROR OUTPUT = {s}\n", .{errOuput});

    const output = std.mem.span(buffer.bp);

    std.debug.print("OUTPUT = {s}\n", .{output});
}
