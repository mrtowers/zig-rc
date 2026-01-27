> [!WARNING]
> **zig-rc** is still WIP. I'm still doing **breaking changes**

# Reference Counting Smart Pointer for Zig

A simple and efficient implementation of a reference counting smart pointer for Zig. This library helps manage the lifetime of heap-allocated objects by automatically tracking references and freeing memory when no references remain.

## Features

- **Automatic Memory Management**: Simplifies memory handling by automatically freeing unused resources.
- **Thread-Safe**: Includes support for atomic reference counting for multithreaded applications via Arc.
- **Lightweight**: Designed to be minimal and efficient.
- **Auto deinit**: Rc and Arc support an optional auto_deinit mode. When enabled, the managed value is automatically deinitialized on the final destroy. If the wrapped type defines a deinit() method, it will be called before the memory is released.
- **Weak Pointers**: Provide non-owning references to managed values without increasing the reference count. Weak pointers do not keep the value alive and can be safely upgraded to a strong `Rc`/`Arc` only if the value still exists. This helps prevent reference cycles and memory leaks, especially in graph-like data structures.

## Installation

### Adding to Your Project

```bash
zig fetch --save git+https://github.com/mrtowers/zig-rc
```
In `build.zig`:

```zig
const rc = b.dependency("zig-rc", .{
    .target = target,
    .optimize = optimize,
});
your_app.root_module.addImport("rc", rc.module("rc"));
```

## Usage

### Basic Example

```zig
const std = @import("std");
const rc = @import("rc");
const Allocator = std.mem.Allocator;

const User = struct {
    name: []u8,
    allocator: Allocator,

    pub fn deinit(self: *const User) u8 { //run automatically by `auto_deinit`
        self.allocator.free(self.name);
        return 0;
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    var ptr = try rc.Rc(User).init(gpa.allocator(), User{
        .allocator = gpa.allocator(),
        .name = try gpa.allocator().dupe(u8, "some user"),
    }, .{
        .auto_deinit = true,
    });
    var ptr2 = ptr.ref();
    _ = ptr.deref();
    _ = ptr2.deref(); // object cleaned up here

}
```

### Weak pointers
```zig
const std = @import("std");
const rc = @import("rc");
const Rc = rc.Rc;
const WeakRc = rc.WeakRc;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    const ptr = try Rc(i32).init(gpa.allocator(), 5, .{});
    defer ptr.deref();

    usingWeak(ptr.weak());
}

fn usingWeak(weak: WeakRc(i32)) void {
    defer weak.deref(); //deref every instance

    if (weak.upgrade()) |number_ref| {
        defer number_ref.deref();
        std.debug.print("number is: {d}\n", .{number_ref.value.*});
    }
}

```

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

Also you can donate me [here](https://buymeacoffee.com/mrtowers), this helps alot! (mainly because i drink a lot of coffee)

Happy coding! 🎉

