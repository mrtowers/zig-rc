const std = @import("std");
const mem = std.mem;
const options = @import("build_options");
const Allocator = mem.Allocator;

/// generates reference counting struct depending on options
pub fn Rc(comptime T: type) type {
    const Callbacks = struct {
        destroyFn: ?*const fn (Allocator, *const T) void = null,
    };

    const ExtraOptions = struct {
        callbacks: Callbacks = .{},
    };

    return struct {
        allocator: Allocator,
        refs: usize,
        value: T,
        lock: if (options.thread_safe) std.Thread.Mutex else void,
        callbacks: Callbacks,

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T, extra: ExtraOptions) !*Self {
            var obj = try allocator.create(Self);
            obj.refs = 1;
            obj.value = value;
            obj.allocator = allocator;
            obj.callbacks = extra.callbacks;
            if (options.thread_safe) obj.lock = std.Thread.Mutex{};
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
                self.deinit();
                return true;
            }

            if (options.thread_safe) self.lock.unlock();

            return false;
        }

        /// immediately frees object, runs destroyFn if not null
        pub fn deinit(self: *const Self) void {
            if (self.callbacks.destroyFn) |f| {
                f(self.allocator, &self.value);
            }
            self.allocator.destroy(self);
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

    var ptr = try Rc(User).init(allocator, User{ .name = try allocator.dupe(u8, "Dawid") }, .{
        .callbacks = .{ .destroyFn = User.destroyFn },
    });
    try testing.expect(std.mem.eql(u8, "Dawid", ptr.value.name));
    const destroyed = ptr.deref();
    try testing.expect(destroyed);
    try testing.expect(User.destroyed);
    const ptr2 = try Rc(u8).init(allocator, 0, .{});
    try testing.expect(ptr2.callbacks.destroyFn == null);
    _ = ptr2.deref();
}
