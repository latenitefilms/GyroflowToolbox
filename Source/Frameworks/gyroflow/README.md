# Gyroflow for Final Cut Pro

## How to build the Rust Dynamic Library

```
cargo build --release
install_name_tool -id "@rpath/libgyroflow.dylib" libgyroflow.dylib
```