# Project Overview

This project, ZeroTTY, is a high-performance, cross-platform terminal emulator written in Zig. It aims for native performance, minimal dependencies, and broad operating system compatibility. The architecture is modular, with clear separation between the core application logic, rendering backend, windowing system, and PTY management.

## Building and Running

### Build Dependencies

*   **Zig:** The project is built using the Zig compiler.
*   **System Libraries:** Depending on the chosen windowing system and rendering backend, you may need to install additional system libraries (e.g., `X11`, `xcb`, `xkbcommon`, `GL`).

### Build Commands

The project uses `build.zig` for its build process. You can build the project with the following command:

```bash
zig build
```

You can also specify the rendering backend and windowing system:

```bash
# Build with OpenGL renderer
zig build -Drender-backend=OpenGL

# Build with Vulkan renderer
zig build -Drender-backend=Vulkan

# Build with D3D11 renderer (for Windows)
zig build -Drender-backend=D3D11
```

### Running the Application

After a successful build, the executable will be located in the `zig-out/bin` directory. You can run it with:

```bash
./zig-out/bin/zerotty
```

### Running Tests

To run the project's tests, use the following command:

```bash
zig build test
```

## Development Conventions

*   **Code Style:** The code follows the standard Zig formatting guidelines.
*   **Modularity:** The codebase is organized into modules with specific responsibilities (e.g., `src/renderer`, `src/window`, `src/pty`).
*   **Cross-Platform:** The code is written to be compatible with multiple operating systems, with platform-specific implementations isolated in their respective files.
*   **Error Handling:** The project uses Zig's error handling mechanism to manage and propagate errors.
*   **Dependencies:** Dependencies are managed through `build.zig.zon` and are fetched and built automatically by the Zig build system.
