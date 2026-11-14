# Compiler installations

No compiler binaries belong in Git. The manifest `linux-x64.json` pins verified download URLs,
versions and hashes for portable archives. Existing local installations are intentionally reusable,
even when their version differs from those pins: every campaign records the actual version.

From the repository root:

```text
python bench/bench.py setup doctor
python bench/bench.py setup install rustc zig ldc2 odin go
python bench/bench.py setup register clang=/absolute/path/to/clang++ swiftc=/absolute/path/to/swiftc
```

Detection checks explicit `BENCH_<TOOL>` overrides, the local registry and PATH. Windows also
retains the Visual Studio, Swift, Java and user-program-directory discovery used by the original
bench. `install` probes an existing tool before downloading anything; it does not overwrite it.
Downloads are hash-verified, extracted into staging, version-probed and only then registered.
A partial or existing destination is never silently replaced. Symlink invocation names are
preserved (`clang++` and `swiftc` select driver behavior). A program named `go` must identify
itself as the Go toolchain, not the board game shipped by some Linux distributions.

`BENCH_COMPILER_ROOT` selects the external install root and its machine-local `local.json`.
Registrations contain absolute paths and must not be committed. Use `BENCH_OUTPUT_ROOT` for
builds/caches. `BENCH_SWC` or `--swc` identifies the compiler under test.

Portable Linux archives cover Rust plus its standard library, Zig, LDC, Odin, Go, Swift
(Ubuntu 24.04 distribution) and .NET SDK. They require a compatible x86-64 Linux userspace.
The Swift package also provides Clang; register its `usr/bin/clang++` if desired. Windows
installation is normally already present: discovery reuses it. Missing Windows tools require
the vendor installer; MSVC cannot be installed from a Linux archive.

Host dependencies still come from the OS: a C/C++ linker and development libraries, binutils
(`objdump`), `taskset`, Java JDK, Node, Python, Lua, LuaJIT, PHP with OPcache and Ruby. On Debian/
Ubuntu the corresponding packages include `build-essential binutils util-linux default-jdk
nodejs python3 lua5.4 luajit php-cli php-opcache ruby`. Use the host package manager for these
and then rerun `doctor`; no privileged package installation happens implicitly. Explicit paths
can be registered individually. Java can use the JDK compiler module when only the `java`
launcher is on PATH. `BENCH_PHP_OPCACHE` identifies the OPcache extension for the JIT variant.

A successful `--version` is only discovery. `smoke` builds and validates an actual task for
selected toolchains and reports SDK/linker/restore failures. In the managed Linux sandbox used
for this refactor, .NET is installed but NuGet initialization can fail on its named mutex;
that environmental failure is not evidence that CoreCLR or NativeAOT was validated.

Frozen Swag references have separate `reference-windows.json` and `reference-linux.json`
manifests and an external immutable store (`BENCH_REFERENCE_ROOT`). Do not repoint a Windows
reference at a Linux executable or combine their histories.
