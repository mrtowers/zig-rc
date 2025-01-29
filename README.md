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
const Rc = @import("rc").Generate(i32, .{});

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    // Create a new reference-counted object
    var ptr = try Rc.init(allocator, 1234);

    // Access the value
    std.debug.print("Value: {}\n", .{ptr.value});

    // Clone the pointer (increments the reference count)
    var ptr_clone = ptr.ref();

    // Both pointers are valid
    std.debug.print("Cloned value: {}\n", .{ptr_clone.value});

    // Release references (automatically decrements the count)
    _ = ptr.deref();
    _ = ptr_clone.deref();
}
```

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

Also you can donate me [here](https://buymeacoffee.com/mrtowers), this helps alot! (mainly becouse i drink a lot of coffee)

Happy coding! 🎉

