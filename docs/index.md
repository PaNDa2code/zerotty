# zerotty

A Cross-Compiled Terminal Emulator

![Logo](assets/images/zerotty.png)

## Description
ZeroTTY is a terminal emulator project. It focuses on **cross-compilation**, **native execution**, and **low-level design** to achieve high **speed and performance** across various operating systems.


## Getting started

1. clone the repository
```bash
git clone github.com/PaNDa2code/zerotty
cd zerotty
```

2. build the project, [more info](build.md)
```bash
zig build -Drender-backend=OpenGL
```

3. run
```bash
./zig-out/bin/zerotty
```
