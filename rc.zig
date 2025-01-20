const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

/// Rc is a reference counting smart pointer
pub fn Rc(comptime T: type) type {
    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,

        const Self = @This();

        /// caller owns value and must free it with allocator
        pub fn init(allocator: Allocator, value: T) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            return obj;
        }

        pub fn ref(self: *Self) *Self {
            self.refs += 1;
            return self;
        }

        pub fn deref(self: *Self) bool {
            self.refs -= 1;
            if (self.refs <= 0) {
                self.allocator.destroy(self);
                return true;
            }
            return false;
        }
    };
}

test {
    const testing = std.testing;
    var obj = try Rc(u8).init(testing.allocator, 4);
    {
        var obj_list = std.ArrayList(*Rc(u8)).init(testing.allocator);
        defer {
            for (obj_list.items) |v| _ = v.deref();
            obj_list.deinit();
        }
        try obj_list.append(obj.ref());
        try obj_list.append(try Rc(u8).init(testing.allocator, 7));
        try testing.expectEqual(obj.refs, 2);
        try testing.expectEqual(obj_list.items[1].refs, 1);
    }
    try testing.expectEqual(obj.refs, 1);
    try testing.expectEqual(obj.deref(), true);
}
