const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = mem.Allocator;

const Options = struct {
    /// automaticaly runs `deinit` method on underlying value
    auto_deinit: bool = false,
};

/// generates reference counting struct depending on options
pub fn Rc(comptime T: type) type {
    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,
        options: Options,

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T, options: Options) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            obj.options = options;
            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference count
        pub fn ref(self: *Self) *Self {
            self.refs += 1;
            return self;
        }

        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) bool {
            assert(self.refs != 0);
            self.refs -= 1;

            if (self.refs <= 0) {
                self.deinit();
                return true;
            }

            return false;
        }

        fn destroy(self: *Self) void {
            if (self.options.auto_deinit) {
                if (std.meta.hasMethod(@TypeOf(self.value), "deinit")) {
                    _ = self.value.deinit();
                }
            }
        }

        /// standard fmt function
        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            if (std.meta.hasMethod(T, "format")) {
                try writer.print("Rc({}): {f}", .{ T, self.value });
                return;
            }

            try writer.print("Rc({}): {any}", .{ T, self.value });
        }

        /// immediately frees object, not recommended, use deref() instead
        pub fn deinit(self: *Self) void {
            self.destroy();
            self.allocator.destroy(self);
        }
    };
}

/// Atomic Rc
pub fn Arc(comptime T: type) type {
    return struct {
        lock: std.Thread.Mutex = .{},
        rc: *Rc(T),

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T, options: Options) !*Self {
            const obj = try allocator.create(Self);
            obj.* = Self{
                .rc = try Rc(T).init(allocator, value, options),
            };

            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference count
        pub fn ref(self: *Self) *Self {
            self.lock.lock();
            defer self.lock.unlock();

            _ = self.rc.ref();
            return self;
        }

        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) bool {
            self.lock.lock();
            assert(self.rc.refs != 0);

            const allocator = self.rc.allocator;

            if (self.rc.deref()) {
                allocator.destroy(self);
                return true;
            }

            self.lock.unlock();
            return false;
        }

        /// standard fmt function
        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            if (std.meta.hasMethod(T, "format")) {
                try writer.print("Arc({}): {f}", .{ T, self.rc.value });
                return;
            }

            try writer.print("Arc({}): {any}", .{ T, self.rc.value });
        }

        /// immediately frees object, not recommended, use deref() instead
        pub fn deinit(self: *Self) void {
            const allocator = self.rc.allocator;
            self.rc.deinit();
            allocator.destroy(self);
        }
    };
}

test "Rc" {
    const testing = std.testing;
    var obj = try Rc(u8).init(testing.allocator, 4, .{});
    {
        var obj_list = try std.ArrayList(*Rc(u8)).initCapacity(testing.allocator, 0);
        defer {
            for (obj_list.items) |v| _ = v.deref();
            obj_list.deinit(testing.allocator);
        }
        try obj_list.append(testing.allocator, obj.ref());
        try obj_list.append(testing.allocator, try Rc(u8).init(testing.allocator, 7, .{}));
        try testing.expectEqual(obj.refs, 2);
        try testing.expectEqual(obj_list.items[1].refs, 1);
    }
    try testing.expectEqual(obj.refs, 1);
    try testing.expectEqual(obj.deref(), true);
    obj = try Rc(u8).init(testing.allocator, 5, .{});
    obj.deinit();
}

test "auto_deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const User = struct {
        allocator: Allocator,
        name: []u8,

        var destroyed = false;

        pub fn deinit(user: *const @This()) void {
            user.allocator.free(user.name);
            destroyed = true;
        }
    };

    const user = User{
        .name = try allocator.dupe(u8, "user"),
        .allocator = allocator,
    };
    var ptr = try Rc(User).init(allocator, user, .{ .auto_deinit = true });
    try testing.expect(std.mem.eql(u8, "user", ptr.value.name));
    const destroyed = ptr.deref();
    try testing.expect(destroyed);
    try testing.expect(User.destroyed);
    const ptr2 = try Rc(u8).init(allocator, 0, .{});
    try testing.expect(ptr2.options.auto_deinit == false);
    try testing.expect(ptr2.deref());
}

test "Arc" {
    const testing = std.testing;
    var obj = try Arc(u8).init(testing.allocator, 4, .{});
    {
        var obj_list = try std.ArrayList(*Arc(u8)).initCapacity(testing.allocator, 0);
        defer {
            for (obj_list.items) |v| _ = v.deref();
            obj_list.deinit(testing.allocator);
        }
        try obj_list.append(testing.allocator, obj.ref());
        try obj_list.append(testing.allocator, try Arc(u8).init(testing.allocator, 7, .{}));
        try testing.expectEqual(obj.rc.refs, 2);
        try testing.expectEqual(obj_list.items[1].rc.refs, 1);
    }
    try testing.expectEqual(obj.rc.refs, 1);
    try testing.expectEqual(obj.deref(), true);
    obj = try Arc(u8).init(testing.allocator, 5, .{});
    obj.deinit();
}

test "deinit with return type" {
    const testing = std.testing;
    const User = struct {
        pub fn deinit(self: *const @This()) u8 {
            _ = self;
            return 0;
        }
    };

    var ptr = try Rc(User).init(testing.allocator, User{}, .{ .auto_deinit = true });
    defer _ = ptr.deref();
}

test "format fn on Rc" {
    const testing = std.testing;
    var writer = std.Io.Writer.Allocating.init(testing.allocator);

    const ptr = try Rc(i32).init(testing.allocator, 13, .{});
    defer _ = ptr.deref();

    try writer.writer.print("{f}", .{ptr});

    const slice = try writer.toOwnedSlice();
    defer testing.allocator.free(slice);
    try testing.expectEqualSlices(u8, "Rc(i32): 13", slice);

    const User = struct {
        name: []const u8,

        pub fn format(self: *const @This(), w: *std.Io.Writer) !void {
            try w.print("User({s})", .{self.name});
        }
    };

    const ptr2 = try Rc(User).init(testing.allocator, .{ .name = "user123" }, .{});
    defer _ = ptr2.deref();

    try writer.writer.print("{f}", .{ptr2});

    const slice2 = try writer.toOwnedSlice();
    defer testing.allocator.free(slice2);
    try testing.expectEqualSlices(u8, "Rc(rc.test.format fn on Rc.User): User(user123)", slice2);
}

test "format fn on Arc" {
    const testing = std.testing;
    var writer = std.Io.Writer.Allocating.init(testing.allocator);

    const ptr = try Arc(i32).init(testing.allocator, 13, .{});
    defer _ = ptr.deref();

    try writer.writer.print("{f}", .{ptr});

    const slice = try writer.toOwnedSlice();
    defer testing.allocator.free(slice);
    try testing.expectEqualSlices(u8, "Arc(i32): 13", slice);

    const User = struct {
        name: []const u8,

        pub fn format(self: *const @This(), w: *std.Io.Writer) !void {
            try w.print("User({s})", .{self.name});
        }
    };

    const ptr2 = try Arc(User).init(testing.allocator, .{ .name = "user123" }, .{});
    defer _ = ptr2.deref();

    try writer.writer.print("{f}", .{ptr2});

    const slice2 = try writer.toOwnedSlice();
    defer testing.allocator.free(slice2);
    try testing.expectEqualSlices(u8, "Arc(rc.test.format fn on Arc.User): User(user123)", slice2);
}
