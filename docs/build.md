# Building from source

You can customize the rendering backend and window system using build arguments.


## Build dependences

- zig compiler (0.15.1)
- SPIR-V tools installed (optional)

## Options

- `-Drender-backend`
    - `OpenGL`
    - `Vulkan` (not fully supported yet)

- `-Dwindow-system`
    - `Xlib` (default on Linux)
    - `Xcb`
    - `Win32` (default on Windows)

---

## recommended build options

#### linux

```bash
zig build -Drender-backend=OpenGL
```

#### Windows

```bash
zig build -Drender-backend=OpenGL
```

#### Cross-compile to Windows from Linux

```ptyhon
zig build -Dtarget=x86_64-windows -Drender-backend=OpenGL
```
