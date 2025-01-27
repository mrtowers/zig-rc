const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

/// Rc is a reference counting smart pointer
pub fn Rc(comptime T: type) type {
    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,
        destroyFn: ?*const fn (Allocator, *const T) void,

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            obj.destroyFn = null;
            return obj;
        }

        const RcExtraOptions = struct {
            destroyFn: ?*const fn (Allocator, *const T) void,
        };

        pub fn initExtra(allocator: Allocator, value: T, options: RcExtraOptions) !*Self {
            var obj = try init(allocator, value);
            obj.destroyFn = options.destroyFn;
            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference couny
        pub fn ref(self: *Self) *Self {
            self.refs += 1;
            return self;
        }

        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) bool {
            if (self.refs == 0) return true;
            self.refs -= 1;
            if (self.refs <= 0) {
                self.destroy();
                return true;
            }
            return false;
        }

        /// immediately frees object, runs destroyFn if not null
        pub fn destroy(self: *const Self) void {
            if (self.destroyFn) |f| {
                f(self.allocator, &self.value);
            }
            self.allocator.destroy(self);
        }
    };
}

/// Rc is a reference counting smart pointer, thread safe
pub fn RcThreadSafe(comptime T: type) type {
    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,
        lock: std.Thread.Mutex,
        destroyFn: ?*const fn (Allocator, *const T) void,

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            obj.lock = std.Thread.Mutex{};
            obj.destroyFn = null;
            return obj;
        }

        pub fn initExtra(allocator: Allocator, value: T, options: Rc(T).RcExtraOptions) !*Self {
            var obj = try init(allocator, value);
            obj.destroyFn = options.destroyFn;
            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference couny
        pub fn ref(self: *Self) *Self {
            self.lock.lock();
            defer {
                self.lock.unlock();
            }
            self.refs += 1;
            return self;
        }

        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) bool {
            self.lock.lock();
            self.refs -= 1;

            if (self.refs <= 0) {
                self.lock.unlock();
                self.destroy();
                return true;
            }

            self.lock.unlock();

            return false;
        }

        /// immediately frees object, runs destroyFn if not null
        pub fn destroy(self: *const Self) void {
            if (self.destroyFn) |f| {
                f(self.allocator, &self.value);
            }
            self.allocator.destroy(self);
        }
    };
}

test "Rc" {
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
    obj = try Rc(u8).init(testing.allocator, 5);
    obj.destroy();
}

test "RcThreadSafe" {
    const testing = std.testing;
    const Thread = std.Thread;

    var obj = try RcThreadSafe(u8).init(testing.allocator, 42);
    _ = &obj;

    var threads: [4]Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try Thread.spawn(.{}, thread_func, .{obj});
    }

    for (&threads) |*thread| {
        thread.join();
    }

    try testing.expect(obj.refs == 1);
    try testing.expect(obj.deref());
    obj = try RcThreadSafe(u8).init(testing.allocator, 5);
    obj.destroy();
}

test "DestroyFn" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const User = struct {
        name: []u8,

        var destroyed = false;

        fn destroyFn(ally: Allocator, user: *const @This()) void {
            ally.free(user.name);
            destroyed = true;
        }
    };

    var ptr = try Rc(User).initExtra(allocator, User{ .name = try allocator.dupe(u8, "Dawid") }, .{
        .destroyFn = User.destroyFn,
    });
    try testing.expect(std.mem.eql(u8, "Dawid", ptr.value.name));
    _ = ptr.deref();
    try testing.expect(User.destroyed);
    const ptr2 = try Rc(u8).init(allocator, 0);
    try testing.expect(ptr2.destroyFn == null);
    _ = ptr2.deref();
}

test "DestroyFnThreadSafe" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const User = struct {
        name: []u8,

        var destroyed = false;

        fn destroyFn(ally: Allocator, user: *const @This()) void {
            ally.free(user.name);
            destroyed = true;
        }
    };

    var ptr = try RcThreadSafe(User).initExtra(allocator, User{ .name = try allocator.dupe(u8, "Dawid") }, .{
        .destroyFn = User.destroyFn,
    });
    try testing.expect(std.mem.eql(u8, "Dawid", ptr.value.name));
    _ = ptr.deref();
    try testing.expect(User.destroyed);
    const ptr2 = try RcThreadSafe(u8).init(allocator, 0);
    try testing.expect(ptr2.destroyFn == null);
    _ = ptr2.deref();
}

fn thread_func(arg: *RcThreadSafe(u8)) !void {
    const testing = std.testing;
    const local_obj = arg.ref();
    defer _ = local_obj.deref();

    const value = local_obj.value;
    try testing.expect(value == 42);
}
