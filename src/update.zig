const std = @import("std");
const git = @import("git");

pub fn main() !void {
    std.log.info("Hello from the update hook!", .{});
    std.log.info("Do you know that 2+2 = {d}?", .{git.add(1, 3)});
}

test "update" {
    try std.testing.expectEqual(1, 1);
}
