const std = @import("std");
const mem = std.mem;
const build_options = @import("build_options");
const Allocator = mem.Allocator;

fn Callbacks(comptime T: type) type {
    return struct {
        destroyFn: ?*const fn (*T) void = null,
    };
}

fn Options(comptime T: type) type {
    return struct {
        callbacks: Callbacks(T) = .{},
    };
}

/// generates reference counting struct depending on options
pub fn Rc(comptime T: type) type {
    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,
        callbacks: Callbacks(T),

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T, extra: Options(T)) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            obj.callbacks = extra.callbacks;
            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference count
        pub fn ref(self: *Self) *Self {
            self.refs += 1;
            return self;
        }

        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) bool {
            self.refs -= 1;

            if (self.refs <= 0) {
                self.deinit();
                return true;
            }

            return false;
        }

        fn destroy(self: *Self) void {
            if (build_options.auto_deinit) {
                if (std.meta.hasMethod(@TypeOf(self.value), "deinit")) {
                    self.value.deinit();
                }
            }
            if (self.callbacks.destroyFn) |f| {
                f(&self.value);
            }
        }

        /// immediately frees object, runs destroyFn if not null
        pub fn deinit(self: *Self) void {
            self.destroy();
            self.allocator.destroy(self);
        }
    };
}

fn Arc(comptime T: type) type {
    return struct {
        lock: std.Thread.Mutex = .{},
        rc: *Rc(T),

        const Self = @This();

        pub fn init(allocator: Allocator, value: T, extra: Options(T)) !*Self {
            const obj = try allocator.create(Self);
            obj.* = Self{
                .rc = try Rc(T).init(allocator, value, extra),
            };

            return obj;
        }

        pub fn ref(self: *Self) *Self {
            self.lock.lock();
            defer self.lock.unlock();

            _ = self.rc.ref();
            return self;
        }

        pub fn deref(self: *Self) bool {
            self.lock.lock();

            const allocator = self.rc.allocator;

            if (self.rc.deref()) {
                allocator.destroy(self);
                return true;
            }

            self.lock.unlock();
            return false;
        }

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

test "destroyFn" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const User = struct {
        allocator: Allocator,
        name: []u8,

        var destroyed = false;

        fn destroyFn(user: *const @This()) void {
            user.allocator.free(user.name);
            destroyed = true;
        }
    };

    const user = User{
        .name = try allocator.dupe(u8, "user"),
        .allocator = allocator,
    };
    var ptr = try Rc(User).init(allocator, user, .{
        .callbacks = .{ .destroyFn = User.destroyFn },
    });
    try testing.expect(std.mem.eql(u8, "user", ptr.value.name));
    const destroyed = ptr.deref();
    try testing.expect(destroyed);
    try testing.expect(User.destroyed);
    const ptr2 = try Rc(u8).init(allocator, 0, .{});
    try testing.expect(ptr2.callbacks.destroyFn == null);
    _ = ptr2.deref();
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

test "auto deinit" {
    //TODO
}
