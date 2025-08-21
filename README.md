# ZeroTTY - A Cross-Compiled Terminal Emulator

![Logo](docs/assets/images/zerotty.png)

## Description
ZeroTTY is a terminal emulator project. It focuses on **cross-compilation**, **native execution**, and **low-level design** to achieve high **speed and performance** across various operating systems.

## Getting started

1. clone the repository
```bash
git clone github.com/PaNDa2code/zerotty
cd zerotty
```

2. build the project, [more info](docs/build.md)
```bash
zig build -Drender-backend=OpenGL
```

3. run
```bash
./zig-out/bin/zerotty
```

## Technologies
Developed primarily in **Zig**, leveraging its capabilities for cross-compilation and system-level programming.

---

## Platform & Architecture Support

Current compatibility status across platforms and architectures:

|OperatingSystem|`x86_64`|`ARM64`|`ARMv7`|
|:-------------:|:------:|:-----:|:-----:|
|**Linux**|🚧|🚧|🚧|
|**Windows**|🚧|🚧|❌|
|**macOS**|🚧|❌|❌|
|**Android**|❌|❌|❌|
|**iOS**|❌|❌|❌|

* **✅ Supported:** Functional and stable.
* **🚧 Experimental:** Under development; may have issues.
* **❌ Not Supported:** No current compatibility.

---

## Core Principles
* **Native Performance:** Prioritizes direct system interaction for speed.
* **Minimal Dependencies:** Reduces overhead and complexity.
* **Cross-Platform:** Designed for broad operating system compatibility.
* **Efficiency:** Focus on low resource usage.

---

## Contribution
Contributions are welcome. Fork the repository and submit pull requests.
