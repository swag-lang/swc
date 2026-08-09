# Bin Portability Roadmap

This file is the cross-unit roadmap for reducing the amount of `bin/` code that a Linux port has
to rewrite. It covers `bin/runtime`, standard modules, and shipped applications. OpenGL is
deliberately excluded. Compiler work is excluded too, except where an intrinsic cannot honestly be
made independent of the host runtime without changing its lowering.

The platform implementations themselves remain owned by
[T-028](todo.core.md#t-028--the-standard-library-is-windows-only),
[T-045](todo.gui.md#t-045--a-second-platform),
[T-066](todo.audio.md#t-066--a-second-platform),
[T-084](todo.scapture.md#t-084--cross-platform-capture-backend), and
[T-100](todo.scrypt.md#t-100--fuse-backend-for-linux-and-macos). This file owns the preparation
across those units: move policy, orchestration, parsing, normalization, and data conversion into
ordinary Swag now, leaving each operating-system backend as a narrow set of mechanisms.

Raw interoperability modules such as `win32`, `gdi32`, `gdiplus`, `xinput`, and `xaudio2` are not
port targets. Explicit adapters such as `Image.from(HBITMAP)` may remain Windows-only. They become
portability debt only when a portable module or application has to mention their types, constants,
message numbers, or calling conventions.

The starting platform-specific body, excluding OpenGL and raw binding modules, is large enough to
justify one coordinated campaign:

| Area | Platform files | Lines |
| --- | ---: | ---: |
| `bin/runtime/os_windows.swg` | 1 | 694 |
| `std/core` (`.win32.swg` and `.xinput.swg`) | 28 | 3,396 |
| `std/gui` (`.win32.swg`, excluding tests) | 5 | 2,448 |
| `std/pixel` (`.win32.swg`, excluding OpenGL and tests) | 3 | 393 |
| `std/audio` XAudio2 backend | 1 | 479 |
| sCapture | 1 | 287 |
| sCrypt, including its platform integration test | 9 | 2,138 |

Those numbers are an inventory, not a deletion target. A small native backend is healthy. The
target is that code above it compiles and is tested without importing a native binding, and that a
new platform implements capabilities rather than copies policy.

---

## Tier A — Establish the boundary before adding Linux

### T-103 — Make portability a checked property rather than a file-name convention

- Define three layers: platform-neutral Swag, narrow host primitives, and optional native
  interoperability. A dependency may point down that list, never back up it.
- Inventory native imports, `#os` branches, native types in public declarations, and direct calls
  from unsuffixed files. The first known exceptions are the Windows blocks in
  `runtime/allocator*.swg`, Audio's unused `Win32` imports, and sCapture's raw message and DPI calls.
- Add a lightweight source check that rejects new native imports and native message/type leakage
  outside approved backend and interoperability paths. Keep an allowlist explicit; matching
  `.win32.swg` alone is not proof that the boundary is good.
- Prove the boundary with a build-only non-Windows configuration as early as possible. It may use
  no-sound and headless implementations at first, but it must compile every platform-neutral file.
- Track both native source lines and, more importantly, native capabilities a new backend must
  implement. Moving 200 lines of orchestration to common Swag is valuable; compressing 200 required
  system calls into a clever wrapper is not.

### T-104 — Split the runtime host ABI and allocator OS primitives

- `bin/runtime/os_windows.swg` currently combines four different things: raw Win32 and UCRT calls,
  TLS/FLS storage, test execution and recovery, and stack-symbol lookup plus presentation. Keep only
  the irreducible host operations in the Windows leaf.
- Move TLS object initialization and copying, test-run bookkeeping and reporting, stack-frame
  formatting, `.swagdbg` parsing, and symbol-table search into common Swag. Native hooks should only
  allocate/get thread storage, capture or resume a context, capture addresses, locate the current
  image and its debug section, write bytes, load a library, and terminate the process.
- Move every `__Win32RT` branch out of `allocator.swg` and `allocator.pages.swg`. Define page
  reserve, commit, decommit, release, current-thread identity, and thread-exit cleanup primitives;
  keep segment, page, size-class, remote-free, guard-placement, and accounting policy common.
- The present non-Windows allocator fallbacks are not equivalent: `@alloc` cannot model reserved
  address space, decommitment, or a guard page, while the counters pretend commit/decommit occurred.
  Do not enable the page path on Linux until `mmap`/protection/release semantics and thread-exit
  cleanup exist.
- Give startup a host ABI that can accept an argument vector directly. Windows may continue to
  parse its process command line, while a Unix entry point supplies `argc`/`argv`; the rest of the
  runtime must see the same `@args` contract.
- Completion means a Linux runtime leaf can be added without copying allocator policy, test
  orchestration, TLS value construction, or symbol formatting from the Windows file.

### T-105 — Reduce the CRT dependency where Swag already owns the semantics

The Windows runtime explicitly links `ucrt` and `vcruntime`. Its declared UCRT surface is limited
to `malloc`/`realloc`/`free`, the four memory block operations, and the scalar `f32`/`f64` math
family. No other production `bin/` module directly imports a C standard library. Treat those three
groups differently:

- `@sqrt` already lowers to `FloatSqrt`, and `@floor`, `@ceil`, `@trunc`, and `@round` already lower
  through the backend's floating-round operations. Verify native and JIT import tables, function
  references, reflection, safety modes, and non-optimized builds, then remove their redundant UCRT
  declarations and wrappers when no emitted path reaches them.
- Constant-sized `@memcpy`, `@memmove`, `@memset`, and `@memcmp` are already emitted inline;
  dynamic sizes still call UCRT. Provide runtime-owned, target-neutral implementations for the
  dynamic path, with correct overlap and `memcmp` ordering. Benchmark small and large blocks before
  replacing the tuned system implementation unconditionally; a size-tiered inline/runtime path is
  acceptable. Ensure compiling those implementations cannot recursively lower back to themselves.
- Make `Crypto.secureClear` a no-elide runtime/compiler primitive or a narrow host primitive. A
  plain Swag loop is not a security guarantee if dead-store elimination may erase it.
- Keep `@alloc`, `@realloc`, and `@free` as an explicit bootstrap/system-allocation boundary until
  T-104 supplies complete page primitives. The Swag allocator itself uses these fallbacks and TLS
  creation uses them before normal allocator state is necessarily available, so routing them
  naively back through the Swag allocator would recurse.
- Audit why `#foreignlib("vcruntime")` is present: no Swag foreign declaration names one of its
  functions, and stack probing is generated internally. Remove it only after inspecting the actual
  imports of representative executables, shared libraries, tests, and JIT artifacts.
- Record a target matrix for hosted builds: Windows UCRT, Linux libc plus libm where required, and
  any future freestanding runtime. A Linux port is not improved by replacing a stable libc call
  with direct kernel syscalls and thereby coupling the runtime to one kernel and architecture.

### T-106 — Make process launch argv-first and keep pipe orchestration common

- `StartInfo.arguments` is one already-quoted string, which makes Windows command-line quoting the
  public contract. Make an argument slice the normal API. Windows alone serializes it with the
  backslash-before-quote rules; Unix passes the vector unchanged. Keep a clearly named raw native
  command-line escape hatch only if an actual caller needs it.
- Move the portable parts of `process.win32.swg` out of the backend: stream-redirection policy,
  ownership and cleanup order, output/error accumulation, draining both pipes while waiting,
  timeout loops, cached exit status, and the convenience `startProcess`/`runProcess` families.
  The host leaf should spawn, poll/wait, terminate, and read/write/close one native endpoint.
- Replace the `#static if WINDOWS` environment-name fold in `ProcessEnvironment` with a target
  policy supplied by the backend. Build the Windows UTF-16 environment block and Unix `envp` only
  at their respective leaves.
- Make `Env.findRunArgument` search the runtime argument vector even during early initialization.
  Its portable name/value matching is currently trapped in `sandbox.win32.swg` only because it
  reparses `GetCommandLineA` before `@args` is populated.
- Preserve the stronger resource contract deliberately. Windows Job Objects account a process
  tree; a Linux implementation needs an explicit process-group/cgroup strategy or must report that
  the capability is unavailable rather than silently measuring only the first child.

### T-107 — Give paths a target policy and filesystems one-entry primitives

- The unsuffixed `path.swg` currently embeds Windows semantics: both slash kinds are separators,
  colon denotes a volume, and equality and extension matching ignore case. Linux paths are
  byte-sensitive, case-sensitive, use `/`, and allow backslash and colon in names. Define a
  compile-time path policy for separators, roots, equality, validity, and normalization, then keep
  the lexical algorithms in common Swag.
- Move the string-only portions of `path.win32.swg` behind that policy. Only resolving against the
  current directory, links, mounts, and actual filesystem state belongs in the native leaf.
- Make the native directory primitive enumerate exactly one directory and return normalized
  metadata. Keep depth-first recursion, `.`/`..` handling, extension/name filters,
  `skipAttributes`, lambda filtering, recursive deletion order, and result construction in common
  Swag.
- Likewise keep `File.openRead`/`openWrite`, sandbox write guards, append positioning, large-transfer
  chunking, full-read/write loops, and stream ownership in common Swag. Native code should map open
  flags and implement one read, write, seek, resize, flush, metadata query, rename, and removal.
- Treat drive letters and Windows file attributes as optional capabilities, not universal
  filesystem concepts. In particular, move `File.availableDriveLetters`, whose product caller is
  sCrypt's WinFsp mount path, into that platform integration.
- Add target-independent lexical tests plus filesystem conformance tests on each host for root
  forms, case, trailing separators, dot segments, Unicode names, links, permissions, partial I/O,
  and recursive traversal.

---

## Tier B — Pull reusable desktop behavior above the native leaves

### T-108 — Replace native public types with portable contracts

- `Core.Env.WindowOptions` exposes Windows style constants and `Window` exposes `HWND` and `HDC`.
  Move this minimal render-host window API out of general environment services, give it portable
  flags, callbacks, scale and opaque storage, and keep native handles/device contexts in an
  explicitly named Windows adapter. OpenGL may consume that adapter without making it the common
  contract.
- Move `WindowLoop` smoke-frame budgeting, move/drop ownership, initial resize dispatch, and
  logical-to-physical size policy into common Swag. Creation, event pumping, native painting,
  monitor DPI queries, and handle lifetime remain backend operations.
- Keep `Pixel.Image` conversions to `HICON`/`HBITMAP`, `Gui.Surface.win32Handle`, and keyboard
  virtual-key conversion as optional Windows interop, not methods required of every target.
  Portable callers should use images, opaque render handles, `Input.Key`, and normalized events.
- Separate generic desktop actions (`openUrl`, reveal a path, enumerate monitors, locale, special
  directories) from platform registration (`registerApplication`, file associations, native
  window creation). Registration belongs in an application-integration module with an explicit
  capability/failure contract, not in the portable core environment namespace.

### T-109 — Build the installed-font catalog in Swag

- `SystemFontFaceInfo` currently stores `LOGFONTW`, so Pixel's public system-font model is a Windows
  descriptor. Replace it with family/subfamily names, normalized style properties, file path, and
  face index. The platform hook should enumerate font files or configured font directories, not
  manufacture a native font handle.
- Use the existing TrueType/OpenType readers (`Face.countFaces`, `familyNameAt`, style/name tables,
  and `Face.loadAt`) to scan files, collections, group faces into families, select regular/bold/
  italic fallbacks, sort, and cache in ordinary Swag.
- Load `TypeFace` from bytes or a file plus face index. Keep the GDI handle path only as a Windows
  compatibility adapter; it must no longer be the only route from a system family to a face.
- A first Linux backend may provide conventional directories. Fontconfig can be added later for
  aliases, user configuration and substitutions without making basic parsing and grouping depend
  on it.
- Coordinate with [T-057](todo.pixel.md#t-057--a-collection-face-is-selected-by-name-and-a-localized-windows-will-miss): selecting by face index also removes the localized-GDI-name
  ambiguity.

### T-110 — Normalize GUI events and separate shell retrieval from caching

- `SysUserEvent` currently carries raw native message numbers. Add typed tray-icon events and a
  platform-neutral application-message event. A backend translates `WM_*`, X11, or Wayland data
  once; application code never switches on it. This is a prerequisite already stated by T-045.
- Give single-instance/application messaging a portable contract. The Windows backend may keep
  `FindWindow`/`SendMessage`; another backend may use a local socket or bus. The public identifier,
  payload, delivery, timeout, and failure semantics must be the same.
- Split `Application`'s system-icon code into a native operation that obtains one image and common
  Swag that caches it, resizes it, appends it to an atlas, and returns a GUI `Icon`. Do the same for
  the generic offscreen `surfaceAt` branch and hot-key command dispatch; only desktop hit testing,
  registration, and key-code translation are native.
- Clipboard typed-value serialization and drag/drop routing are already common. Keep the native
  files limited to ownership protocols and platform formats; use Pixel codecs for image conversion
  rather than growing a second decoder in each backend.
- Keep `Surface` position clamping, headless fallbacks, state updates, and command posting common.
  A native surface backend should only create/destroy/show/move the host window, translate input
  and window-manager events, manage clipboard/drag/drop/tray integration, and expose an opaque
  renderer handle.

### T-111 — Remove accidental Windows coupling from Audio

- Delete the unused `Win32` imports from `bus.swg` and `voice.swg`. Define WAVE extensible GUIDs
  with a portable packed UUID value instead of `Win32.GUID`, and name the channel mask as the WAVE
  speaker-mask field it is rather than as a general native handle.
- Replace the repeated `#os == Windows` dispatch in `driver/backend.swg` with a backend interface or
  operation table. Driver selection, validation, voice/bus lifecycle, streaming-buffer rotation,
  gain conversion, state transitions, and codec work stay common; XAudio2 is one implementation.
- Keep the no-sound backend available on every target and add the Linux backend under T-066 without
  changing `SoundFile`, `Voice`, or `Bus`. A build that explicitly selects XAudio2 on Linux should
  fail as an unavailable optional backend, not make the Audio module itself Windows-dependent.

### T-112 — Extract the remaining small common algorithms from Core backends

- Gamepads: make a native backend return one raw portable snapshot, then normalize stick/trigger
  ranges, map buttons, apply hysteresis thresholds, and derive directional pseudo-buttons in common
  Swag. XInput vibration and connection errors remain native.
- Threads: keep context cloning, temporary-allocator setup/release, user-lambda dispatch,
  cooperative-stop state, handle ownership, and wait-many orchestration common. Backends create,
  start, join, yield, sleep, identify, and set priority. Account for the current create-suspended
  contract explicitly because POSIX does not provide it directly.
- Timers: implement lifecycle, periodic rescheduling, callback/context dispatch, and cancellation
  races once in Swag over a small monotonic-wait/wake primitive or a common scheduler. Do not clone
  Windows timer-queue policy into every backend.
- Time: keep `Timestamp.utcNow = Timestamp.fromDateTime(DateTime.utcNow())` and native-structure to
  `DateTime` field assignment common; backends provide wall-clock fields and monotonic ticks.
- Console: keep null/silent handling and variadic formatting in common Swag, then send bytes through
  a native stdout writer. Color selection, terminal capability, prompting and encoding remain host
  concerns.
- Cryptographic randomness: keep request chunking and fill-completely/retry policy common over one
  OS random-fill primitive. Secure clearing stays governed by T-105.

### T-113 — Make shipped applications depend only on normalized platform services

- sCapture's unsuffixed `capturerectwnd.swg` and `inplaceeditwnd.swg` import Win32/GDI without using
  them; remove those imports. Move the DPI-awareness scope in unsuffixed `screenshot.swg` into the
  Windows capture backend.
- Replace sCapture's `WM_USER`, `WM_LBUTTONDBLCLK`, and `WM_RBUTTONDOWN` branches with the tray and
  application-message events from T-110. Keep screen acquisition, cursor compositing, and
  window-under-rectangle queries in `screenshot.win32.swg`; all capture/editor policy stays common
  for T-084.
- Move sCrypt's available-drive-letter query and every WinFsp/registry/guardian concern under its
  Windows mount backend. The application chooses an abstract mount destination and consumes mount
  status; the WinFsp backend maps that to a drive letter and T-100 maps it to a Unix mount point.
- Require an application source check: outside a named platform backend and platform integration
  test, no shipped application may import a raw OS module or compare a native constant.

---

## Tier C — Optional ownership, not a Linux prerequisite

### T-114 — Decide deliberately whether Swag should ship its own libm

`@sin`, `@cos`, `@tan`, the hyperbolic and inverse functions, `@atan2`, `@log`, `@log2`, `@log10`,
`@exp`, `@exp2`, and `@pow` are language intrinsics but their runtime implementation currently
calls UCRT. On a hosted Linux target the direct equivalent is the platform math library. Calling a
library does not make an operation less intrinsic: the compiler owns its signature, constant
semantics and safety checks, while the final implementation may still be a runtime call.

Do not make a handwritten transcendental library a prerequisite for Linux. Unlike `sqrt` and basic
rounding, these operations have no suitable scalar x64 instruction to lower to. A production
implementation has to handle argument reduction for huge inputs, subnormals, infinities, NaNs,
signed zero, every `pow` corner case, bounded error or correct rounding, and competitive
performance. A simple Taylor series is not an implementation of that contract.

Own this layer only if Swag chooses at least one product goal that needs it: freestanding builds,
bit-reproducible math across supported hosts, independence from each platform's ABI and quality, or
a deliberately specified accuracy/performance tradeoff. If that decision is made:

- start from a proven, permissively licensed algorithm corpus and port it into audited Swag rather
  than designing approximations ad hoc;
- state the error and special-value contract separately for `f32` and `f64`, including whether
  results are correctly rounded, faithfully rounded, or only bounded in ulps;
- add exhaustive `f32` checking where feasible, high-precision differential and adversarial vectors
  for `f64`, identities only as secondary tests, and benchmarks against each supported system libm;
- make compile-time folding use the same specified semantics. It currently uses the compiler
  host's C++ math library, so replacing only the runtime would make a constant expression and the
  same runtime expression disagree across hosts;
- retain hardware/compiler lowerings for `sqrt`, rounding, absolute value, min/max, fused multiply
  add, bit operations, and atomics instead of routing them through the software math library.

The decision is complete when the hosted Linux ABI can ship without it and the optional owned-libm
goal has measurable reasons, semantics, provenance, and acceptance tests. “Other languages do it”
is not by itself a requirement; mature languages make different choices according to whether they
target an operating system, a freestanding environment, deterministic numerics, or all three.

