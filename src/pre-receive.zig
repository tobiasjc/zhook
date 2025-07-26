const std = @import("std");
const git = @import("git");

pub fn main() !void {
    std.log.info("Hello from the pre-receive hook!", .{});
    std.log.info("Do you know that 1+1 = {d}?", .{git.add(2, 0)});
}

test "pre-receive" {
    try std.testing.expectEqual(1, 1);
}
