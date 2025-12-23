> [!WARNING]
> **zig-rc** is still WIP. I'm still doing **breaking changes**

# Reference Counting Smart Pointer for Zig

A simple and efficient implementation of a reference counting smart pointer for Zig. This library helps manage the lifetime of heap-allocated objects by automatically tracking references and freeing memory when no references remain.

## Features

- **Automatic Memory Management**: Simplifies memory handling by automatically freeing unused resources.
- **Thread-Safe (Optional)**: Includes optional support for atomic reference counting for multithreaded applications.
- **Lightweight**: Designed to be minimal and efficient.

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

    pub fn deinit(self: *const User) u8 {
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

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

Also you can donate me [here](https://buymeacoffee.com/mrtowers), this helps alot! (mainly becouse i drink a lot of coffee)

Happy coding! 🎉

