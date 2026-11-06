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
   adapters. The `linux`, `curl`, `faudio`, `win32`, `gdi32`, `gdiplus`, `xinput`, and `xaudio2` modules belong here, as do
   explicit adapters such as `Image.from(HBITMAP)`. Interoperability modules may depend only on
   other interoperability modules. Portable code never needs them merely to use Core, GUI, Pixel,
   Audio, or a shipped application.

OpenGL remains an explicit native API. Its Linux EGL/XCB context adapter is the rendering
prerequisite for the existing Pixel OpenGL backend; portable GUI contracts do not expose EGL
handles. Tests that exercise a native integration point remain in the host layer and must be
selected explicitly.

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
all C++ tests pass, including filesystem, JIT and native validation. The generated target defaults
to the compiler host; Linux selects System V, the Linux runtime and GNU-linked ELF output.
`--os linux` and `--os windows` explicitly override the target.
Native executables cover startup, arguments, synchronization and fault recovery. Static/shared
imports execute initialization and cleanup, and published .so files survive executable relocation.
ELF executables and shared libraries resolve imports at load time: the lazy System V resolver
would clobber the fifth and sixth Swag argument registers (R10/R11) on the first call.
Compile-time shared imports execute through the same runtime hooks. Dynamic load/unload preserves
shared context and initialization/final-close ownership. Shared libraries are position-independent,
reject text relocations, and protect relocated constants after loading. Native `--debug` emits DWARF
source/function/type records and recorded stack-home locations, validated with readelf, addr2line and GDB.
Optimized-away variables and richer type/location records remain. Executables reuse eligible
self-contained function objects from an output-local ELF cache; compiler identity, IR/ABI changes,
source-coordinate changes and damaged cache bytes invalidate reuse. Unchanged executable modules also
relink cached objects against updated static dependencies; API changes or damaged/missing caches
fall back to compilation.
The C++ JIT page allocator and `bin/runtime`'s `__hostPage*` hooks have separate tests.

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
| Foreign calls, argument/return classification and callee-save registers | `src/Backend/ABI/`, Windows x64 | System V scalar/aggregate calls, source parameter homes, result storage and cached JIT invokers tested against native C; native suites also cover owned-value cleanup and over-aligned values |
| Object emission, linking, startup, dynamic imports and debug artifacts | `src/Backend/Native/`, `src/Backend/Linker/`, COFF/PE/PDB | ELF objects and internal executable/shared/archive linking, exact argc/argv startup, static/shared dependencies and relocatable publication execute; compile-time shared imports and dynamic load/unload preserve runtime context. PIC function pointers and relative unwind records permit strict text-relocation rejection. DWARF source stepping and recorded stack-home variables work; eligible function objects and whole-module relink inputs use checksummed ELF caches. Richer debug records remain |
| Runtime reserve/commit/decommit/release and allocation-base lookup | `bin/runtime/os.win32.swg`, `__hostPage*` | Linux reservation tracking over mmap/mprotect/madvise/munmap; JIT probes cover decommit/recommit and base lookup; native ELF fork probe keeps child reservations out of the parent registry; native electric allocator probes fault on a guard page and freed payload, and a dynamic consumer resolves and frees a DLL-owned block; JIT and native ELF probes recover protected-page faults |
| Runtime TLS and thread-exit cleanup | `bin/runtime/os.win32.swg`, `__hostTls*`, `__hostThreadStorage*` | pthread keys; compiler-owned callbacks use a host destructor, drain live-thread values and finish active cleanup before JIT code is unmapped; rearming and explicit deletion are tested |
| Runtime threads, priorities, processor count, pool ceiling and work pressure | `bin/runtime/os.win32.swg`, `__hostThread*`, `__hostWorkPressure` | pthread creation/join and procfs counters pass JIT probes; scheduler contention, affinity limits and cgroup pressure need broader coverage |
| Runtime locks and condition variables | `bin/runtime/os.win32.swg`, `__hostLock*`, `__hostCondition*`, `MutexRW` | Futex storage with JIT and native mutex, reader/writer and timeout checks; broader contention and fork coverage remain |
| Runtime process-wide storage and singleton identity across shared modules | `bin/runtime/os.win32.swg`, `__hostProcessStorage`, `__hostProcessSingleton` | memfd/procfs anchors pass same-process identity, size checks and C++/Swag interoperability; native dynamic-library tests preserve shared context through repeated load/unload. Fork and broader ownership stress remain |
| Runtime monotonic clock and hardware features | `bin/runtime/os.win32.swg`, `__hostMonotonic*`, `__hostHasAvx2` | CLOCK_MONOTONIC and glibc CPU feature queries pass JIT probes |
| Runtime arguments, byte output, native library loading and termination | `bin/runtime/os.win32.swg`, `__osCommandLine`, `__printString`, `__loaddll`, `__exit*` | Native argc/argv preserves empty values, spaces, quotes, backslashes and UTF-8 across shared imports; dynamically loaded modules retain argument bytes and order through unload; JIT libc termination calls report compiler diagnostics |
| Runtime test fault recovery, stack capture, image and debug-section access | `bin/runtime/os.win32.swg`, `__hostTest*`, `__hostCatchCall`, `__hostResume`, `__captureStack`, `__host*DebugSection` | Linux signal recovery passes JIT and native ELF probes, including stack overflow, captured-error cleanup and prior-handler restoration; linked ELF runtime symbol tables resolve native frames across executable, static and shared modules; stripped images retain ordinary panic reporting. Bootstrap JIT and native probes cover empty/bounded destinations, extreme skip counts, ordered frames and addresses without loader-owned images |
| Runtime hosted math | `bin/runtime/os.win32.swg`, UCRT imports | glibc/libm bindings execute through System V; GNU ELF linking supplies libc and libm |
| Standard raw Linux ABI | `bin/std/modules/linux` | glibc descriptors, filesystem, inotify/poll, spawn/wait/signals, mappings, entropy, secure-clear, loader and clock declarations; isolated and cross-module calls pass in JIT and native ELF |
| Core directories, files, streams, mappings, metadata, paths and watches | `bin/std/modules/core/src/filesystem/*.win32.swg` | Streams/mappings, directories, statx metadata, POSIX opening/sharing and inotify watches implemented. Mount-namespace directory roots, mount-ID-based remote filesystem classification, available-space queries and a borrowed FileStream descriptor are available. Descriptor ownership, filesystem-space and split-pipe read cases pass JIT/native. Public filesystem (8), mapped memory (2) and watcher (10) cases pass JIT/native; overflow, interrupted I/O, partial writes and permission stress remain |
| Core processes, environment, hardware, native libraries, errors and sandbox | `bin/std/modules/core/src/system/*.win32.swg` | Native libraries, environment snapshots, image path, XDG/user directories, locale, sandbox paths and argv-based process ownership implemented. A native peer passes stdin/stdout/stderr redirection with its own standard descriptors closed; continuous output respects a finite wait deadline, and a grandchild retaining pipes does not extend direct-child waits in JIT/native. A 64-process native stress peer finds no leaked descriptors after successful and failed launches; late owner close still reaps after Core stops its reaper. A dynamically loaded module queues a live child and unloads while shared Core reaps it in native and JIT consumers. Isolated native peers verify live environment mutation, stable snapshots, early sandbox arming and refusal of an outside write; a separate native importer sees sandbox arming before its own init hooks. Linux filesystem and process failures map to portable missing-file/invalid-name errors while retaining native error IDs; focused cases pass JIT/native. `openFile`/`openUrl` use `xdg-open`; file reveal uses bounded D-Bus requests. The application chooser uses optional libsystemd and OpenURI portal v3 with a retained connection; native private-bus integration covers real file/directory descriptors, lifecycle and failures. Public cases and separate importers pass JIT/native; interactive desktop validation remains |
| Core hardware and identity | `bin/std/modules/core/src/system/hardware.win32.swg`, `process.win32.swg` | Affinity count, six-byte adapter address and process/thread IDs implemented; public hardware and thread identity cases pass JIT/native |
| Core thread/event primitives, wall clocks and timers | `bin/std/modules/core/src/thread/*.win32.swg`, `src/time/*.win32.swg` | Nanosecond clocks, UTC/local calendars, sleep/yield, pthread lifecycle and shared timer worker implemented. Public thread (7), unnamed event (5), timer lifecycle (2), common context (4) and clock/calendar (31) cases pass JIT/native; a native New York peer verifies both daylight-saving transitions. Per-thread nice priorities preserve the caller and inherited baseline, report permission failures and reject exited threads; DevMode/Release JIT/native checks and a native 65-thread wait-batch stress case pass, while named events and broader lifetime stress remain |
| Core console, debugger and secure-memory operations | `bin/std/modules/core/src/diagnostics/*.win32.swg`, `src/crypto/security.win32.swg` | Entropy, secure clearing, byte console I/O and terminal color implemented. Public crypto cases pass JIT/native; five focused cases also pass in native Release. Release ELF disassembly retains HmacSha256.compute → drop → clear → explicit_bzero@plt after the secret's last use. A linked console consumer covers pipes, pseudo-terminals, Unicode, large transfers and interrupted I/O. Debugger presence and breaks pass ptrace checks; exact-byte stderr diagnostics preserve errno and handle closed pipes without fatal SIGPIPE. Launch/attach remains |
| Core keyboard, mouse and gamepad acquisition | `bin/std/modules/core/src/input/`, Windows and XInput leaves | evdev gamepad state/rumble ownership and X11 keyboard/pointer/cursor operations implemented. Normalization, absent-device and desktop cases pass JIT/native, including standard PC keypad polling with NumLock/Shift and the server modifier mapping; real gamepads, IME and event routing remain unvalidated or incomplete |
| Core native windows, monitors, focus and cursor visibility | `bin/std/modules/core/src/system/desktop.*.swg`, `environment.window.*.swg` | XCB window ownership, move-safe render descriptors, placement/hide/focus requests, opt-in independent close handling, bounded event dispatch, focus callbacks, optional RandR queries and XFixes cursor visibility implemented. Xvfb cases pass JIT/native, including unavailable displays/extensions; GUI compositor/input cases also run with Openbox. Connection-loss stress and broader desktop policy remain |
| Network TCP and HTTP transport | `bin/std/modules/net/src/tcp.win32.swg`, `src/http/client.win32.swg` | Blocking IPv4 TCP implemented in `tcp.linux.swg`; ordinary loopback and tagged ownership/error/SIGPIPE cases pass JIT/native. HTTP/HTTPS uses lazy libcurl with strict TLS, proxy support and bounded transfers; direct/proxy and separate-importer cases pass JIT/native. IPv6, UDP, resolver APIs and cancellation remain |
| OpenGL context and native entry points | `bin/std/modules/ogl/src/ogl.win32.swg` | EGL/XCB OpenGL 3.3 compatibility context owner; framebuffer transfer, independent context cleanup, shared resources and closed-window rejection pass JIT/native under Xvfb/Mesa software rendering. Nine JIT/native cases cover context/resource lifetimes, including two surfaceless cases without a display. Pixel and GUI presentation are tested; physical GPUs and native Wayland remain |
| Pixel installed fonts, native image adapters and render-thread integration | `bin/std/modules/pixel/src/text/*.win32.swg`, `src/image/image.win32.swg`, `src/render/renderthread.win32.swg` | Linux installed-font catalog, family/style selection and fallback implemented; renderer-owned EGL contexts support independently owned window surfaces. Eight presentation/readback/resource integration cases and three CPU/OpenGL parity scenes pass JIT/native; 92 native golden tests pass against the current categorized corpus. Text parity keeps the four-level channel bound with explicit floating-point MSDF interpolation. GUI integration compares complete XCB window pixels with render-target output under a compositor. Full application and physical GPU coverage remain; native Windows image-handle adapters stay optional |
| Audio device, voices, buses and streaming | `bin/std/modules/audio/src/driver/xaudio2.swg` | FAudio provides real voices, submix buses and streaming callbacks. PCM disk-output tests cover gain, pitch, routing, seek, looping and repeated stop; missing libraries/devices and shared teardown regressions pass. Physical audio hardware and full application playback remain unvalidated |
| GUI surfaces, presentation, native text, input, cursor, clipboard and drag/drop | `bin/std/modules/gui/src/*.win32.swg`, `src/paint/cursor.win32.swg` | XCB/EGL surfaces, XKB input, cursor, EWMH state, XEmbed tray, clipboard and XDND are implemented. Fourteen JIT/native integration cases cover full window pixels under a compositor, XTEST input (including keypad press/release identity across NumLock changes), XSettings, headless GPU, UTF-8/PNG/INCR clipboard, and XDND/XDS peers. Full applications, dynamic keyboard-map changes, native Wayland, IME and accessibility remain |
| Capture screen/window/region acquisition | `bin/apps/modules/swagcapture/src/screenshot/screenshot.win32.swg` | X11 root-image, region, cursor and window-query backend passes two JIT/native integration cases; full app execution, compositor validation and native Wayland capture remain |
| Vault filesystem mount and host lifecycle | `bin/apps/modules/swagvault/src/winfsp/`, `src/autounmount.win32.swg` | FUSE3 callbacks and real read/write, rename, open-unlink, unmount and read-only remount pass in JIT/native execution. Linux volume locking is implemented. Private D-Bus peers validate login-session lock/unlock, idle and sleep-inhibitor lifetime; real X11 idle queries pass JIT/native under Xvfb. Physical-session integration, GUI mount workflows and packaging remain |
| Application desktop integration and packaging | Swag Capture, Swag Scope and Swag Vault module setup; Core/GUI/Pixel services above | Per-user XDG desktop entries and MIME associations use optional GIO, preserve existing defaults and pass isolated native registration, quoting, unavailable-library, failed-write and sandbox tests. Linux application packaging and registration consumers remain |

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
| GNU/Linux x86-64 | glibc (`libc.so.6`) and libm (`libm.so.6`, `-lm`) | POSIX threads (`-pthread`) and `dlopen`/`dlsym` (`-ldl` for toolchain compatibility) | System V JIT execution; internally linked ELF executables, shared objects and GNU static archives without a C compiler or external linker, with CRT startup, `-lc -lm -ldl -pthread` |
| Freestanding | No selected contract | No implicit hosted services | Not implemented |

Modern glibc integrates pthread and dl symbols into libc; keeping the toolchain flags does not
mean shipping private copies of those libraries. The Linux C++ host-test launcher currently uses
libc/libstdc++, `-pthread` and `-ldl`, with the C++ toolchain supplying its own startup objects.
Linux runtime math should use the host libm before considering a separately owned implementation.
