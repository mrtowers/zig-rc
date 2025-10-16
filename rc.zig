const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const Options = struct {
    thread_safe: bool = false,
};

/// generates reference counting struct depending on options
pub fn Generate(comptime T: type, comptime options: Options) type {
    const ExtraOptions = struct {
        destroyFn: ?*const fn (Allocator, *const T) void = null,
    };

    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,
        lock: if (options.thread_safe) std.Thread.Mutex else void,
        destroyFn: ?*const fn (Allocator, *const T) void,

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            if (options.thread_safe) obj.lock = std.Thread.Mutex{};

            obj.destroyFn = null;
            return obj;
        }

        pub fn initExtra(allocator: Allocator, value: T, extra_options: ExtraOptions) !*Self {
            var obj = try init(allocator, value);
            obj.destroyFn = extra_options.destroyFn;
            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference count
        pub fn ref(self: *Self) *Self {
            if (options.thread_safe) {
                self.lock.lock();
                defer {
                    self.lock.unlock();
                }
            }
            self.refs += 1;
            return self;
        }

        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) bool {
            if (options.thread_safe) self.lock.lock();
            self.refs -= 1;

            if (self.refs <= 0) {
                if (options.thread_safe) self.lock.unlock();
                self.destroy();
                return true;
            }

            if (options.thread_safe) self.lock.unlock();

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
    const Rc = Generate(u8, .{});
    var obj = try Rc.init(testing.allocator, 4);
    {
        var obj_list = try std.ArrayList(*Rc).initCapacity(testing.allocator, 0);
        defer {
            for (obj_list.items) |v| _ = v.deref();
            obj_list.deinit(testing.allocator);
        }
        try obj_list.append(testing.allocator, obj.ref());
        try obj_list.append(testing.allocator, try Rc.init(testing.allocator, 7));
        try testing.expectEqual(obj.refs, 2);
        try testing.expectEqual(obj_list.items[1].refs, 1);
    }
    try testing.expectEqual(obj.refs, 1);
    try testing.expectEqual(obj.deref(), true);
    obj = try Rc.init(testing.allocator, 5);
    obj.destroy();
}

test "RcThreadSafe" {
    const testing = std.testing;
    const Thread = std.Thread;
    const RcThreadSafe = Generate(u8, .{ .thread_safe = true });

    const utils = struct {
        fn thread_func(arg: *RcThreadSafe) !void {
            const local_obj = arg.ref();
            defer _ = local_obj.deref();

            const value = local_obj.value;
            try testing.expect(value == 42);
        }
    };

    var obj = try RcThreadSafe.init(testing.allocator, 42);
    _ = &obj;

    var threads: [4]Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try Thread.spawn(.{}, utils.thread_func, .{obj});
    }

    for (&threads) |*thread| {
        thread.join();
    }

    try testing.expect(obj.refs == 1);
    try testing.expect(obj.deref());
    obj = try RcThreadSafe.init(testing.allocator, 5);
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

    const Rc = Generate(User, .{});

    var ptr = try Rc.initExtra(allocator, User{ .name = try allocator.dupe(u8, "Dawid") }, .{
        .destroyFn = User.destroyFn,
    });
    try testing.expect(std.mem.eql(u8, "Dawid", ptr.value.name));
    _ = ptr.deref();
    try testing.expect(User.destroyed);
    const Rc2 = Generate(u8, .{});
    const ptr2 = try Rc2.init(allocator, 0);
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

    const RcThreadSafe = Generate(User, .{ .thread_safe = true });

    var ptr = try RcThreadSafe.initExtra(allocator, User{ .name = try allocator.dupe(u8, "Dawid") }, .{
        .destroyFn = User.destroyFn,
    });
    try testing.expect(std.mem.eql(u8, "Dawid", ptr.value.name));
    _ = ptr.deref();
    try testing.expect(User.destroyed);
    const RcThreadSafe2 = Generate(u8, .{ .thread_safe = true });
    const ptr2 = try RcThreadSafe2.init(allocator, 0);
    try testing.expect(ptr2.destroyFn == null);
    _ = ptr2.deref();
}
