const std = @import("std");

pub fn add(a: usize, b: usize) usize {
    return a + b;
}

test "git" {
    try std.testing.expectEqual(1, 1);
}
