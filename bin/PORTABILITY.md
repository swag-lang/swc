# Portability boundary

Code under `bin/` belongs to one of three dependency layers. Dependencies point down this list;
they never point back up it.

1. **Platform-neutral Swag** owns policy, orchestration, parsing, normalization, data conversion,
   and public contracts. This is every runtime, standard-module, and shipped-application source
   not assigned below. Neutral sources may call portable operations whose implementation is
   supplied by a host leaf, but they do not import a native module, branch on `#os`, name a native
   type or constant, or call a native API.
2. **Host primitives** own the irreducible operating-system mechanisms behind those contracts.
   The Windows runtime leaf, the named Core/GUI/Pixel/Audio Windows leaves, Swag Capture's capture
   leaf, and Swag Vault's `winfsp/` directory belong here. Module setup files may select these leaves
   and their raw dependencies. A host leaf may depend on optional native interoperability, but its
   portable API uses neutral values or opaque native storage.
3. **Optional native interoperability** owns raw ABI declarations and deliberately native
   adapters. The `linux`, `win32`, `gdi32`, `gdiplus`, `xinput`, and `xaudio2` modules belong here, as do
   explicit adapters such as `Image.from(HBITMAP)`. Interoperability modules may depend only on
   other interoperability modules. Portable code never needs them merely to use Core, GUI, Pixel,
   Audio, or a shipped application.

OpenGL is outside this boundary: the portability roadmap deliberately excludes it. Tests that
exercise a native integration point remain in the host layer and must be selected explicitly.

`tools/portability.bat` checks that no Swag script launchers remain in `tools/`. The former
source audit of this contract has been retired; a platform-looking suffix is not an approval. Add a path only when
it owns a narrow host mechanism or optional adapter, and keep transitional public exceptions tied
to their backlog entry. Every repository test campaign runs the same audit before compiling.

## Host capability inventory

Update this inventory in the same change as an adapter or portability contract. Entries describe
implemented capabilities, not native source-line counts. `Windows` below means an implementation
exists in the named owner; it does not imply that a Windows campaign ran on the Linux host.
`Missing` means Linux has no implementation of that contract, even when common policy exists.

The Linux host-adapter boundary is `python3 tools/linux-host.py`, on Linux x86-64 with
GCC 14 and C++23, glibc 2.36 or later and Linux 5.9 or later (pidfds, subreapers and
`close_range` must be permitted). It tests actual compiler host adapters independently.
`tools/linux-build.py` builds complete DevMode and Release compilers. Lexer/parser suites and
all C++ tests pass, including filesystem, JIT and native validation. The default generated target
remains Windows; `--os linux` selects System V, the Linux runtime and GNU-linked ELF output.
Native executables cover startup, arguments, synchronization and fault recovery. Static/shared
imports execute initialization and cleanup, and published .so files survive executable relocation.
Compile-time shared imports execute through the same runtime hooks. Dynamic load/unload, PIC
and source-level DWARF still need integration. The C++ JIT page allocator and
`bin/runtime`'s `__hostPage*` hooks have separate tests.

| Capability | Owner / Windows adapter | Linux implementation |
| --- | --- | --- |
| Compiler executable pages, protection, proximity reservation, physical release | `src/Support/Os/Os.Windows.cpp` | `src/Support/Os/Os.Memory.Linux.cpp`; native host tests |
| Compiler immutable mapped-cache generations | `src/Support/Os/ReadOnlyFileMapping.Windows.cpp` | `src/Support/Os/ReadOnlyFileMapping.Linux.cpp`; native host tests |
| Compiler directory identity locks and atomic cache publication | `src/Support/Os/DirectoryLock.h`, `src/Main/FileSystem.IO.cpp` | `DirectoryLock.Linux.cpp` and common I/O tests; advisory inode locking, alias coordination and waiter identity recheck. Concurrent directory cleanup still needs coordination |
| Compiler terminal, environment, executable path and process identity | `src/Support/Os/Os.Windows.cpp` | `Os.Console.Linux.cpp`, `Os.Linux.cpp`; terminal/redirection and environment tests |
| Compiler process lifecycle and output capture | `src/Support/Os/Os.Windows.cpp` | `Os.Process.Linux.cpp` and common `ProcessOutput.cpp`; argv, capture/filtering, silent/noisy timeouts, detached descendants, callback unwinding and caller SIGKILL tests |
| Compiler shared-library lookup and TLS | `src/Support/Os/Os.Windows.cpp` | `Os.Module.Linux.cpp`, `Os.Thread.Linux.cpp`; shared-library C calls, search paths and thread isolation tests |
| Compiler file-user diagnostics and explicit Windows cross-toolchain inputs | `src/Support/Os/Os.Windows.cpp` | `Os.File.Linux.cpp`; executable, descriptor and mapped-file users by inode; mounted SDK discovery through explicit environment paths |
| Compiler native stack capture and symbol resolution | `src/Support/Os/Os.Windows.cpp` | `Os.Stack.Linux.cpp`; bounded unwinding, frame skipping and demangled ELF symbols; safe diagnostic reads use `process_vm_readv` or checked procfs fallback. DWARF source locations remain unavailable |
| Compiler signal stacks and generated-code unwinding | `src/Support/Os/Os.Windows.cpp`, `src/Backend/JIT/` | Guarded per-thread alternate stacks, DWARF CIE/FDE construction and libgcc registration; native tests cover stack overflow, generated frames and C++ cleanup after a generated fault. The fault boundary preserves C++ cleanup and rejects native faults. Instruction-level CFI follows the control-flow graph, including multiple returns, dynamic stack allocation, saved registers and indirect jumps |
| Compiler startup CPU/OS-state check | `src/Main/HostCpuGuard.cpp` | ELF preinit guard checks GCC’s x86-64-v3 predicate, including OS AVX state; rejection tested before C++ initialization |
| Foreign calls, argument/return classification and callee-save registers | `src/Backend/ABI/`, Windows x64 | System V scalar/aggregate calls, source parameter homes, result storage and cached JIT invokers tested against native C; owned-value cleanup and native runtime integration remain |
| Object emission, linking, startup, dynamic imports and debug artifacts | `src/Backend/Native/`, `src/Backend/Linker/`, COFF/PE/PDB | ELF objects, GNU executable/archive linking, exact argc/argv startup, static/shared dependencies and relocatable publication execute; compile-time shared imports also execute; dynamic load/unload, PIC and source-level DWARF remain |
| Runtime reserve/commit/decommit/release and allocation-base lookup | `bin/runtime/os.win32.swg`, `__hostPage*` | Linux reservation tracking over mmap/mprotect/madvise/munmap; JIT probes cover decommit/recommit and base lookup; JIT and native ELF probes recover protected-page faults |
| Runtime TLS and thread-exit cleanup | `bin/runtime/os.win32.swg`, `__hostTls*`, `__hostThreadStorage*` | pthread keys; compiler-owned callbacks use a host destructor, drain live-thread values and finish active cleanup before JIT code is unmapped; rearming and explicit deletion are tested |
| Runtime threads, priorities, processor count, pool ceiling and work pressure | `bin/runtime/os.win32.swg`, `__hostThread*`, `__hostWorkPressure` | pthread creation/join and procfs counters pass JIT probes; scheduler contention, affinity limits and cgroup pressure need broader coverage |
| Runtime locks and condition variables | `bin/runtime/os.win32.swg`, `__hostLock*`, `__hostCondition*`, `MutexRW` | Futex storage with JIT and native mutex, reader/writer and timeout checks; broader contention and fork coverage remain |
| Runtime process-wide storage and singleton identity across shared modules | `bin/runtime/os.win32.swg`, `__hostProcessStorage`, `__hostProcessSingleton` | memfd/procfs anchors pass same-process identity, size checks and C++/Swag interoperability; native cross-module and fork lifetime coverage remain |
| Runtime monotonic clock and hardware features | `bin/runtime/os.win32.swg`, `__hostMonotonic*`, `__hostHasAvx2` | CLOCK_MONOTONIC and glibc CPU feature queries pass JIT probes |
| Runtime arguments, byte output, native library loading and termination | `bin/runtime/os.win32.swg`, `__osCommandLine`, `__printString`, `__loaddll`, `__exit*` | Native argc/argv preserves empty values, spaces, quotes, backslashes and UTF-8 across shared imports; JIT libc termination calls report compiler diagnostics |
| Runtime test fault recovery, stack capture, image and debug-section access | `bin/runtime/os.win32.swg`, `__hostTest*`, `__hostCatchCall`, `__hostResume`, `__captureStack`, `__host*DebugSection` | Linux signal recovery passes JIT and native ELF probes, including stack overflow, captured-error cleanup and prior-handler restoration; source-level stack resolution remains |
| Runtime hosted math | `bin/runtime/os.win32.swg`, UCRT imports | glibc/libm bindings execute through System V; GNU ELF linking supplies libc and libm |
| Standard raw Linux ABI | `bin/std/modules/linux` | glibc descriptors, filesystem, inotify/poll, spawn/wait/signals, mappings, entropy, secure-clear, loader and clock declarations; isolated and cross-module calls pass in JIT and native ELF |
| Core directories, files, streams, mappings, metadata, paths and watches | `bin/std/modules/core/src/filesystem/*.win32.swg` | Stream/mapping, directory/path, enumeration, statx metadata and file-mutation leaves added; raw and imported ABI tests pass. POSIX opening/sharing and inotify watching added, with explicit recursive rescan/cancellation limits; public ownership, root-link deletion and watcher tests remain blocked |
| Core processes, environment, hardware, native libraries, errors and sandbox | `bin/std/modules/core/src/system/*.win32.swg` | Native library, environment lookup, exit and XDG/user-database special-directory leaves added; Linux keeps runtime argv and case-sensitive environment names. Linux sandbox canonicalization, case handling and early lookup added; argv-first launch API and its consumers migrated; public ownership/enforcement tests remain blocked, and Linux process creation/ownership and desktop services remain |
| Core hardware and identity | `bin/std/modules/core/src/system/hardware.win32.swg`, `process.win32.swg` | Linux affinity count, six-byte adapter address and process/thread IDs added; raw layouts tested JIT/native, public tests pending |
| Core thread/event primitives, wall clocks and timers | `bin/std/modules/core/src/thread/*.win32.swg`, `src/time/*.win32.swg` | Nanosecond monotonic clock, UTC/local calendar, sleep/yield and gated pthread lifecycle added, pending Core tests; Linux priority currently supports Normal only; shared timer worker has monotonic deadlines and cancellation, with public tests pending |
| Core console, debugger and secure-memory operations | `bin/std/modules/core/src/diagnostics/*.win32.swg`, `src/crypto/security.win32.swg` | Entropy, secure clearing, byte console I/O and terminal color leaves added, pending Core tests and pseudo-terminal coverage; debugger remains missing |
| Core keyboard, mouse and gamepad acquisition | `bin/std/modules/core/src/input/`, Windows and XInput leaves | evdev gamepad discovery implementation added, pending Core and hardware validation; gamepad state/vibration, keyboard and mouse remain missing |
| Network TCP and HTTP transport | `bin/std/modules/net/src/tcp.win32.swg`, `src/http/client.win32.swg` | Missing |
| Pixel installed fonts, native image adapters and render-thread integration | `bin/std/modules/pixel/src/text/*.win32.swg`, `src/image/image.win32.swg`, `src/render/renderthread.win32.swg` | Missing; OpenGL is outside this roadmap |
| Audio device, voices, buses and streaming | `bin/std/modules/audio/src/driver/xaudio2.swg` | `nosound.swg` is selected in source; no real device backend or Linux execution validation |
| GUI surfaces, presentation, native text, input, cursor, clipboard and drag/drop | `bin/std/modules/gui/src/*.win32.swg`, `src/paint/cursor.win32.swg` | Missing; headless policy is not a native desktop backend |
| Capture screen/window/region acquisition | `bin/apps/modules/swagcapture/src/screenshot/screenshot.win32.swg` | Missing |
| Vault filesystem mount and host lifecycle | `bin/apps/modules/swagvault/src/winfsp/`, `src/autounmount.win32.swg` | Missing FUSE backend |
| Scope/Prism desktop integration and application packaging | Application module setup and Core/GUI/Pixel services above | Missing Linux packaging and desktop registration |

Portable algorithms, codecs and application models consume these capabilities. Their neutral
source status does not prove that their entire module can compile on Linux. Optional raw Windows
interop remains deliberately Windows-only; it does not need a Linux implementation.

The `bin/runtime/os.linux*.swg` bootstrap executes guarded compile-time code and host-boundary
probes for glibc TLS, thread cleanup, futex synchronization, page reservations, process anchors,
monotonic clocks, procfs pressure, libm and argument vectors. C declarations and callbacks resolve
the ABI of their own compilation, including a Linux compiler instance inside a Windows-targeted
process. Compiler-owned pthread callbacks retire before JIT code is unmapped; both compiler
builds pass teardown and joined-thread probes. Native ELF startup, exact argument vectors,
synchronization and signal recovery pass dedicated fixtures; this does
not establish complete runtime or standard-module coverage.

## Hosted library matrix

The first Linux bootstrap target is GNU/Linux x86-64 with glibc. Other libc implementations,
architectures and freestanding builds have no validated target contract yet.

| Target | C/math libraries | Thread and loader interfaces | Current link support |
| --- | --- | --- | --- |
| Windows x86-64 | UCRT (`ucrtbase` at runtime, `ucrt` link input) | Kernel32 and the existing Windows host imports | Windows toolchain discovery, COFF and PE |
| GNU/Linux x86-64 | glibc (`libc.so.6`) and libm (`libm.so.6`, `-lm`) | POSIX threads (`-pthread`) and `dlopen`/`dlsym` (`-ldl` for toolchain compatibility) | System V JIT execution; ELF executables and archives through GNU `cc`/`ar`, with CRT startup, `-lc -lm -ldl -pthread` |
| Freestanding | No selected contract | No implicit hosted services | Not implemented |

Modern glibc integrates pthread and dl symbols into libc; keeping the toolchain flags does not
mean shipping private copies of those libraries. The Linux C++ host-test launcher currently uses
libc/libstdc++, `-pthread` and `-ldl`, with the C++ toolchain supplying its own startup objects.
Linux runtime math should use the host libm before considering a separately owned implementation.
