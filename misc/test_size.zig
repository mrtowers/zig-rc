const std = @import("std");
const Rc = @import("../rc.zig").Rc;
pub fn main() !void {
    std.debug.print("rc size: {}\n", .{@sizeOf(Rc(void))});
}
