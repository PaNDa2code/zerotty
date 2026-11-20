# Building from source

You can customize the rendering backend and window system using build arguments.


## Build dependences

- zig compiler (0.17.0)

---

## build examples

```
zig build --release=safe
```

#### Cross-compile to Windows from Linux

```
zig build --release=safe -Dtarget=x86_64-windows
```
