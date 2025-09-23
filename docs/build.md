# Building from source

You can customize the rendering backend and window system using build arguments.


## Build dependences

- zig compiler (0.15.1)
- glslang-tools installed (optional)

## Options

- `-Drender-backend`
    - `OpenGL`
    - `Vulkan` (default)

- `-Dwindow-system`
    - `Xlib`
    - `Xcb` (default on Linux)
    - `Win32` (default on Windows)

- `-Dno-lsp-check`
    - `true`
    - `false` (default)

    this disables a step called `check` that used automatically by [zls](https://github.com/zigtools/zls) to load build configuration

- `-Ddisable-renderer-debug`
    - `true` (default in release builds)
    - `false` (default in debug builds)

    this disables debuging callbacks and validation layers

---

## build examples

```
zig build -Doptimize=ReleaseFast -Dwindow-system=Xcb -Dno-lsp-check -Drender-backend=Vulkan
```

#### Cross-compile to Windows from Linux

```
zig build -Dtarget=x86_64-windows -Drender-backend=OpenGL -Ddisable-renderer-debug
```
