# bare-io
bare bones low-level I/O library written in Zig   for non-blocking APIs and for building high performance I/O apps.


## cross compile for other platforms
### arm-linux 32 bit

```
zig build  -Doptimize=ReleaseSafe -Dtarget=arm-linux-musleabihf examples
```
