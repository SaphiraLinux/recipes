# Rust bootstrap trust boundary

Rust 1.97.1 cannot be bootstrapped from GCC alone. Akadata starts with the
official Rust 1.96.0 compiler, standard library, and Cargo components for
`x86_64-unknown-linux-musl`. Their release date, URLs, and SHA-256 values are
recorded in `bootstrap.lock` and duplicated in the Stage4 source lock.

The official binaries are unpacked only below the rustc source unit's private
build directory. They compile the Rust 1.97.1 stage1 compiler and standard
library. Stage1 then compiles the stage2 compiler, standard library, Cargo,
rustfmt, Clippy, and rustdoc. Only stage2 installation output enters the APK
staging root; no 1.96.0 file is copied into a final package. The `rust-src`
package is copied directly from the separately fingerprinted 1.97.1 source
unit and has no binary-bootstrap input.

The binary bootstrap is the explicit trust boundary. Rust source, vendored
Cargo dependencies, the three bootstrap components, system LLVM, and the
Akadata build policy together determine the final unit fingerprint. Replacing
the bootstrap with a diverse-source bootstrap is outside this package's trust
claim.
