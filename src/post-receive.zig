const std = @import("std");
const git = @import("git");

pub fn main() !void {
    std.log.info("Hello from the post-receive hook!", .{});
    std.log.info("Do you know that 3+3 = {d}?", .{git.add(1, 5)});
}

test "post-receive" {
    try std.testing.expectEqual(1, 1);
}
