---
layout: default
title: Build
---

## 🚧 Building

You can customize the rendering backend and window system using build arguments.

### ✨ Supported Options

- `-Drender-backend`
  - `OpenGL` (default)
  - `Vulkan`
  - `D3D11` (Windows only)

- `-Dwindow-system`
  - `Xlib` (default on Linux)
  - `Xcb`
  - `Win32` (default on Windows)
{: .cli-options}

---

### 🛠 Example Builds

#### ✅ Linux + OpenGL + Xlib
```bash
zig build -Dtarget=native -Drender-backend=OpenGL -Dwindow-system=Xlib
```
✅ Windows + D3D11 + Win32

```bash
zig build -Dtarget=x86_64-windows -Drender-backend=D3D11 -Dwindow-system=Win32
```

✅ Cross-compile to Windows from Linux

```bash
zig build -Dtarget=x86_64-windows -Drender-backend=OpenGL -Dwindow-system=Win32
```
