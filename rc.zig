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
        strong_count: usize = 1,
        weak_count: usize = 0,
        value: *T,
        options: Options,

        const Self = @This();

        /// caller owns value and must free it with deref()
        pub fn init(allocator: Allocator, value: T, options: Options) !*Self {
            const obj = try allocator.create(Self);
            const value_obj = try allocator.create(T);
            value_obj.* = value;

            obj.* = .{
                .allocator = allocator,
                .value = value_obj,
                .options = options,
            };

            return obj;
        }

        /// use when adding to other struct or taking ownership, increments reference count
        pub fn ref(self: *Self) *Self {
            self.strong_count += 1;
            return self;
        }

        //TODO remove from docs `returns true if destroyed`
        /// use when droping ownership, decreases reference counting, frees data when refs == 0, returns true if destroyed
        pub fn deref(self: *Self) void {
            assert(self.strong_count != 0);
            self.strong_count -= 1;

            if (self.strong_count <= 0) {
                self.destroyValue();
                if (self.weak_count <= 0) {
                    self.deinit();
                }
            }
        }

        fn derefWeak(self: *Self) void {
            self.weak_count -= 1;
            if (self.strong_count <= 0 and self.weak_count <= 0) {
                self.deinit();
            }
        }

        /// returns weak reference increasing weak count, dereference with deref()
        pub fn weak(self: *Self) WeakRc(T) {
            assert(self.strong_count != 0);

            self.weak_count += 1;

            return WeakRc(T){ .rc = self };
        }

        fn destroyValue(self: *Self) void {
            if (self.options.auto_deinit) {
                if (std.meta.hasMethod(T, "deinit")) {
                    _ = self.value.deinit();
                }
            }
            self.allocator.destroy(self.value);
        }

        /// standard fmt function
        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            if (std.meta.hasMethod(T, "format")) {
                try writer.print("Rc({}): {f}", .{ T, self.value });
                return;
            }

            try writer.print("Rc({}): {any}", .{ T, self.value.* });
        }

        /// immediately frees object, not recommended, use deref() instead
        pub fn deinit(self: *Self) void {
            if (self.strong_count > 0) {
                self.destroyValue();
            }
            self.allocator.destroy(self);
        }
    };
}

pub fn WeakRc(comptime T: type) type {
    return struct {
        rc: *Rc(T),

        const Self = @This();

        /// returns strong Rc reference, dereference with deref()
        pub fn upgrade(self: *const Self) ?*Rc(T) {
            if (self.isAlive()) {
                return self.rc.ref();
            }

            return null;
        }

        /// increases weak counter, returns weak reference, dereference with deref()
        pub fn ref(self: *const Self) WeakRc(T) {
            self.rc.weak_count += 1;

            return self.*;
        }

        pub fn deref(self: *const Self) void {
            self.rc.derefWeak();
        }

        pub fn isAlive(self: *const Self) bool {
            return self.rc.strong_count > 0;
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
        pub fn deref(self: *Self) void {
            self.lock.lock();
            assert(self.rc.strong_count != 0);

            const allocator = self.rc.allocator;

            const rc_destroyed = self.rc.strong_count == 1 and self.rc.weak_count == 0;

            self.rc.deref();

            if (rc_destroyed) {
                allocator.destroy(self);
                return;
            }

            self.lock.unlock();
        }

        fn derefWeak(self: *Self) void {
            self.rc.weak_count -= 1;
            if (self.rc.strong_count <= 0 and self.rc.weak_count <= 0) {
                self.deinit();
            }
        }

        /// returns weak reference increasing weak count, dereference with deref()
        pub fn weak(self: *Self) WeakArc(T) {
            assert(self.rc.strong_count != 0);

            self.rc.weak_count += 1;

            return WeakArc(T){ .arc = self };
        }

        /// standard fmt function
        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            if (std.meta.hasMethod(T, "format")) {
                try writer.print("Arc({}): {f}", .{ T, self.rc.value });
                return;
            }

            try writer.print("Arc({}): {any}", .{ T, self.rc.value.* });
        }

        /// immediately frees object, not recommended, use deref() instead
        pub fn deinit(self: *Self) void {
            const allocator = self.rc.allocator;
            self.rc.deinit();
            allocator.destroy(self);
        }
    };
}

pub fn WeakArc(comptime T: type) type {
    return struct {
        arc: *Arc(T),

        const Self = @This();

        /// returns strong Arc reference, dereference with deref()
        pub fn upgrade(self: *const Self) ?*Arc(T) {
            if (self.isAlive()) {
                return self.arc.ref();
            }

            return null;
        }

        /// increases weak counter, returns weak reference, dereference with deref()
        pub fn ref(self: *const Self) WeakArc(T) {
            self.arc.rc.weak_count += 1;

            return self.*;
        }

        pub fn deref(self: *const Self) void {
            self.arc.derefWeak();
        }

        pub fn isAlive(self: *const Self) bool {
            return self.arc.rc.strong_count > 0;
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
        try testing.expectEqual(obj.strong_count, 2);
        try testing.expectEqual(obj_list.items[1].strong_count, 1);
    }
    try testing.expectEqual(obj.strong_count, 1);
    obj.deref();
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
    const ptr = try Rc(User).init(allocator, user, .{ .auto_deinit = true });
    try testing.expect(std.mem.eql(u8, "user", ptr.value.name));
    ptr.deref();
    try testing.expect(User.destroyed);
    const ptr2 = try Rc(u8).init(allocator, 0, .{});
    try testing.expect(ptr2.options.auto_deinit == false);
    ptr2.deref();
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
        try testing.expectEqual(obj.rc.strong_count, 2);
        try testing.expectEqual(obj_list.items[1].rc.strong_count, 1);
    }
    try testing.expectEqual(obj.rc.strong_count, 1);
    obj.deref();
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

test "WeakRc" {
    const testing = std.testing;

    {
        const ptr = try Rc(i32).init(testing.allocator, 0, .{});
        defer ptr.deref();

        const weak = ptr.weak();
        defer weak.deref();

        try testing.expectEqual(1, ptr.strong_count);
        try testing.expectEqual(1, ptr.weak_count);

        {
            var weak2 = weak.ref();
            defer weak2.deref();

            try testing.expectEqual(2, ptr.weak_count);
        }
        try testing.expectEqual(1, ptr.weak_count);

        const ptr_ref = weak.upgrade() orelse unreachable;
        defer ptr_ref.deref();

        try testing.expectEqual(2, ptr.strong_count);
        try testing.expectEqual(1, ptr.weak_count);
    }

    const ptr = try Rc(i32).init(testing.allocator, 0, .{});
    const weak = ptr.weak();

    try testing.expectEqual(1, ptr.weak_count);
    try testing.expectEqual(1, ptr.strong_count);
    ptr.deref();
    try testing.expectEqual(1, ptr.weak_count);
    try testing.expectEqual(0, ptr.strong_count);

    try testing.expect(weak.upgrade() == null);

    weak.deref();
}
test "WeakArc" {
    const testing = std.testing;

    {
        const ptr = try Arc(i32).init(testing.allocator, 0, .{});
        defer ptr.deref();

        const weak = ptr.weak();
        defer weak.deref();

        try testing.expectEqual(1, ptr.rc.strong_count);
        try testing.expectEqual(1, ptr.rc.weak_count);

        {
            var weak2 = weak.ref();
            defer weak2.deref();

            try testing.expectEqual(2, ptr.rc.weak_count);
        }
        try testing.expectEqual(1, ptr.rc.weak_count);

        const ptr_ref = weak.upgrade() orelse unreachable;
        defer ptr_ref.deref();

        try testing.expectEqual(2, ptr.rc.strong_count);
        try testing.expectEqual(1, ptr.rc.weak_count);
    }

    const ptr = try Arc(i32).init(testing.allocator, 0, .{});
    const weak = ptr.weak();

    try testing.expectEqual(1, ptr.rc.weak_count);
    try testing.expectEqual(1, ptr.rc.strong_count);
    ptr.deref();
    try testing.expectEqual(1, ptr.rc.weak_count);
    try testing.expectEqual(0, ptr.rc.strong_count);

    try testing.expect(weak.upgrade() == null);

    weak.deref();
}
