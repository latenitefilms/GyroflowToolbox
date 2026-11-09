//! Gives CubeCL's build-ID reader the engine dylib's own Mach-O UUID.
//!
//! The upstream `buildid` crate names the executable header. A cdylib has a dylib header instead;
//! this linker alias (kept private by Rust's export list) resolves that one symbol without allowing
//! arbitrary undefined symbols or depending on the host application's UUID. Unit-test executables
//! use their normal header.
fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-alias,__mh_dylib_header,__mh_execute_header");
    }
}
