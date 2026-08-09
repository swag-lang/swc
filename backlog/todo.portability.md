# Bin Portability Roadmap

This file is the cross-unit roadmap for reducing the amount of `bin/` code that a Linux port has
to rewrite. It covers `bin/runtime`, standard modules, and shipped applications. OpenGL is
deliberately excluded. Compiler work is excluded too, except where an intrinsic cannot honestly be
made independent of the host runtime without changing its lowering.

The platform implementations themselves remain owned by
[T-028](todo.core.md#t-028--process-services-have-no-second-platform-backend),
[T-045](todo.gui.md#t-045--no-second-platform-surface-and-presentation-backend),
[T-066](todo.audio.md#t-066--a-second-platform),
[T-084](todo.scapture.md#t-084--cross-platform-capture-backend), and
[T-100](todo.scrypt.md#t-100--no-linux-fuse-backend). This file owns the preparation
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

### T-103 — Portability boundary violations have no source check

Inventory native imports, `#os` branches, native types in public declarations, and direct calls
  from unsuffixed files. The first known exceptions are the Windows blocks in
  `runtime/allocator*.swg`, Audio's unused `Win32` imports, and sCapture's raw message and DPI calls.
- Add a lightweight source check that rejects new native imports and native message/type leakage
  outside approved backend and interoperability paths. Keep an allowlist explicit; matching
  `.win32.swg` alone is not proof that the boundary is good.
- Related: T-334, T-266, T-267

### T-334 — The portability dependency layers are not defined

Define three layers: platform-neutral Swag, narrow host primitives, and optional native
interoperability. A dependency may point down that list, never back up it. State which paths own
each layer before T-103 turns the rule into a source check.

- Related: T-103

### T-266 — No build-only non-Windows portability configuration

Prove the boundary with a build-only non-Windows configuration as early as possible. It may use
  no-sound and headless implementations at first, but it must compile every platform-neutral file.

- Related: T-103

### T-267 — Portability progress has no capability inventory

Track both native source lines and, more importantly, native capabilities a new backend must
  implement. Moving 200 lines of orchestration to common Swag is valuable; compressing 200 required
  system calls into a clever wrapper is not.

- Related: T-103, T-266

### T-104 — Define a minimal runtime host ABI

`bin/runtime/os_windows.swg` combines raw calls with portable policy. Define a minimal host ABI for
thread storage, context/address capture, image/debug-section access, byte output, library loading,
and process termination; keep only those irreducible operations in the Windows leaf.

- Related: T-268, T-269, T-270, T-271

### T-268 — Runtime TLS value policy remains in the Windows leaf

Move TLS object initialization and copying into common Swag. Native hooks only allocate and get
thread storage.

- Related: T-104, T-327, T-328

### T-327 — Runtime test orchestration remains in the Windows leaf

Move test-run bookkeeping, recovery policy, and reporting into common Swag over the context and
termination primitives from T-104.

- Related: T-104, T-268

### T-328 — Stack-symbol presentation remains in the Windows leaf

Move stack-frame formatting, `.swagdbg` parsing, and symbol-table search into common Swag. Leave
only address capture and image/debug-section access native.

- Related: T-104, T-140

### T-269 — Allocator policy still contains Windows branches

Move every `__Win32RT` branch out of `allocator.swg` and `allocator.pages.swg`. Define page
  reserve, commit, decommit, release, current-thread identity, and thread-exit cleanup primitives;
  keep segment, page, size-class, remote-free, guard-placement, and accounting policy common.

- Related: T-104, T-165, T-270

### T-270 — Linux page-allocation primitives do not exist

The present non-Windows allocator fallbacks are not equivalent: `@alloc` cannot model reserved
  address space, decommitment, or a guard page, while the counters pretend commit/decommit occurred.
  Implement `mmap`/protection/release semantics and thread-exit
  cleanup exist.

- Related: T-165, T-269

### T-271 — Runtime startup cannot accept an argument vector

Give startup a host ABI that can accept an argument vector directly. Windows may continue to
  parse its process command line, while a Unix entry point supplies `argc`/`argv`; the rest of the
  runtime must see the same `@args` contract.

- Related: T-104, T-106, T-279

### T-105 — Basic math intrinsics retain redundant UCRT wrappers

The Windows runtime explicitly links `ucrt` and `vcruntime`. Its declared UCRT surface is limited
to `malloc`/`realloc`/`free`, the four memory block operations, and the scalar `f32`/`f64` math
family. No other production `bin/` module directly imports a C standard library. Treat those three
groups differently:

`@sqrt` already lowers to `FloatSqrt`, and `@floor`, `@ceil`, `@trunc`, and `@round` already lower
  through the backend's floating-round operations. Verify native and JIT import tables, function
  references, reflection, safety modes, and non-optimized builds, then remove their redundant UCRT
  declarations and wrappers when no emitted path reaches them.

- Related: T-272, T-273, T-274, T-275, T-276, T-114

### T-272 — Dynamic memory block intrinsics depend directly on UCRT

Constant-sized `@memcpy`, `@memmove`, `@memset`, and `@memcmp` are already emitted inline;
  dynamic sizes still call UCRT. Provide runtime-owned, target-neutral implementations for the
  dynamic path, with correct overlap and `memcmp` ordering. Benchmark small and large blocks before
  replacing the tuned system implementation unconditionally; a size-tiered inline/runtime path is
  acceptable. Ensure compiling those implementations cannot recursively lower back to themselves.

- Related: T-105

### T-273 — `Crypto.secureClear` has no no-elide primitive

Make `Crypto.secureClear` a no-elide runtime/compiler primitive or a narrow host primitive. A
  plain Swag loop is not a security guarantee if dead-store elimination may erase it.

- Related: T-105, T-089

### T-274 — Bootstrap allocation has no documented system boundary

Keep `@alloc`, `@realloc`, and `@free` as an explicit bootstrap/system-allocation boundary until
  T-104 supplies complete page primitives. The Swag allocator itself uses these fallbacks and TLS
  creation uses them before normal allocator state is necessarily available, so routing them
  naively back through the Swag allocator would recurse.

- Related: T-104, T-269

### T-275 — The runtime links `vcruntime` without an identified imported symbol

Audit why `#foreignlib("vcruntime")` is present: no Swag foreign declaration names one of its
  functions, and stack probing is generated internally. Remove it only after inspecting the actual
  imports of representative executables, shared libraries, tests, and JIT artifacts.

- Related: T-105

### T-276 — Hosted runtime library dependencies have no target matrix

Record a target matrix for hosted builds: Windows UCRT, Linux libc plus libm where required, and
  any future freestanding runtime. A Linux port is not improved by replacing a stable libc call
  with direct kernel syscalls and thereby coupling the runtime to one kernel and architecture.

- Related: T-105, T-114

### T-106 — Make process launch argv-first

- `StartInfo.arguments` is one already-quoted string, which makes Windows command-line quoting the
  public contract. Make an argument slice the normal API. Windows alone serializes it with the
  backslash-before-quote rules; Unix passes the vector unchanged. Keep a clearly named raw native
  command-line escape hatch only if an actual caller needs it.

### T-277 — Process orchestration remains in the Windows backend

Move the portable parts of `process.win32.swg` out of the backend: stream-redirection policy,
  ownership and cleanup order, output/error accumulation, draining both pipes while waiting,
  timeout loops, cached exit status, and the convenience `startProcess`/`runProcess` families.
  The host leaf should spawn, poll/wait, terminate, and read/write/close one native endpoint.

- Related: T-028, T-106, T-280

### T-278 — Process environment construction embeds Windows policy

Replace the `#static if WINDOWS` environment-name fold in `ProcessEnvironment` with a target
  policy supplied by the backend. Build the Windows UTF-16 environment block and Unix `envp` only
  at their respective leaves.

- Related: T-106, T-135

### T-279 — Early argument lookup reparses the Windows command line

Make `Env.findRunArgument` search the runtime argument vector even during early initialization.
  Its portable name/value matching is currently trapped in `sandbox.win32.swg` only because it
  reparses `GetCommandLineA` before `@args` is populated.

- Related: T-271, T-106

### T-280 — Process-tree resource accounting has no portable capability contract

Preserve the stronger resource contract deliberately. Windows Job Objects account a process
  tree; a Linux implementation needs an explicit process-group/cgroup strategy or must report that
  the capability is unavailable rather than silently measuring only the first child.

- Related: T-028, T-277

### T-107 — Give paths a target policy

- The unsuffixed `path.swg` currently embeds Windows semantics: both slash kinds are separators,
  colon denotes a volume, and equality and extension matching ignore case. Linux paths are
  byte-sensitive, case-sensitive, use `/`, and allow backslash and colon in names. Define a
  compile-time path policy for separators, roots, equality, validity, and normalization, then keep
  the lexical algorithms in common Swag.

### T-281 — Portable path algorithms remain in the Windows file

Move the string-only portions of `path.win32.swg` behind T-107's target policy. Only resolving against the
  current directory, links, mounts, and actual filesystem state belongs in the native leaf.

- Related: T-107

### T-282 — Directory recursion remains in the native backend

Move depth-first traversal and `.`/`..` handling into common Swag.

- Related: T-132, T-107, T-377, T-378, T-379

### T-377 — Directory filtering remains in the native backend

Move extension/name filters, `skipAttributes`, and lambda filtering into common traversal policy.

- Related: T-282

### T-378 — Recursive deletion order remains in the native backend

Build recursive removal order in common Swag over one-entry enumeration and one native removal
primitive.

- Related: T-282, T-283

### T-379 — Native directory backends do not expose one-entry enumeration

Define one native operation that enumerates exactly one directory and returns normalized metadata;
keep result construction in common Swag.

- Related: T-132, T-282

### T-283 — File orchestration remains in the native backend

Keep `File.openRead`/`openWrite`, sandbox write guards, append positioning, large-transfer
  chunking, full-read/write loops, and stream ownership in common Swag. Native code should map open
  flags and implement one read, write, seek, resize, flush, metadata query, rename, and removal.

- Related: T-132, T-107

### T-284 — Drive-letter enumeration lives in portable filesystem services

Treat drive letters and Windows file attributes as optional capabilities, not universal
  filesystem concepts. In particular, move `File.availableDriveLetters`, whose product caller is
  sCrypt's WinFsp mount path, into that platform integration.

- Related: T-307

### T-285 — Filesystems have no cross-host conformance suite

Add filesystem conformance tests on each host for Unicode names, links, permissions, partial I/O,
and recursive traversal.

- Related: T-132, T-282, T-283, T-329

### T-329 — Paths have no target-independent lexical conformance suite

Test root forms, case policy, trailing separators, dot segments, invalid names, and normalization
without touching the filesystem.

- Related: T-107, T-281, T-285

---

## Tier B — Pull reusable desktop behavior above the native leaves

### T-108 — Replace native types in the render-host window contract

- `Core.Env.WindowOptions` exposes Windows style constants and `Window` exposes `HWND` and `HDC`.
  Move this minimal render-host window API out of general environment services, give it portable
  flags, callbacks, scale and opaque storage, and keep native handles/device contexts in an
  explicitly named Windows adapter. OpenGL may consume that adapter without making it the common
  contract.

### T-286 — `WindowLoop` policy remains in the Windows backend

Move `WindowLoop` smoke-frame budgeting, move/drop ownership, initial resize dispatch, and
  logical-to-physical size policy into common Swag. Creation, event pumping, native painting,
  monitor DPI queries, and handle lifetime remain backend operations.

- Related: T-108

### T-287 — Optional Windows interop is mixed into portable types

Keep `Pixel.Image` conversions to `HICON`/`HBITMAP`, `Gui.Surface.win32Handle`, and keyboard
  virtual-key conversion as optional Windows interop, not methods required of every target.
  Portable callers should use images, opaque render handles, `Input.Key`, and normalized events.

- Related: T-108, T-110

### T-288 — Desktop actions and application registration share one environment API

Separate generic desktop actions (`openUrl`, reveal a path, enumerate monitors, locale, special
  directories) from platform registration (`registerApplication`, file associations, native
  window creation). Registration belongs in an application-integration module with an explicit
  capability/failure contract, not in the portable core environment namespace.

- Related: T-108, T-135

### T-109 — Replace the native installed-font descriptor

- `SystemFontFaceInfo` currently stores `LOGFONTW`, so Pixel's public system-font model is a Windows
  descriptor. Replace it with family/subfamily names, normalized style properties, file path, and
  face index. The platform hook should enumerate font files or configured font directories, not
  manufacture a native font handle.

### T-289 — Installed-font scanning is not common Swag

Use the existing TrueType/OpenType readers (`Face.countFaces`, `familyNameAt`, style/name tables,
  and `Face.loadAt`) to scan configured files and collections into portable face descriptors.

- Related: T-109, T-290, T-291, T-380

### T-380 — Installed-font family grouping is not common Swag

Group scanned descriptors into families, select regular/bold/italic fallbacks, sort, and cache the
catalog independently of platform enumeration.

- Related: T-109, T-289

### T-290 — A system face cannot load directly from file and face index

Load `TypeFace` from bytes or a file plus face index. Keep the GDI handle path only as a Windows
  compatibility adapter; it must no longer be the only route from a system family to a face.

- Related: T-057, T-109, T-289

### T-291 — Linux has no installed-font source

A first Linux backend may provide conventional directories. Fontconfig can be added later for
  aliases, user configuration and substitutions without making basic parsing and grouping depend
  on it.

- Related: T-289

### T-110 — Normalize native GUI messages into typed events

`SysUserEvent` currently carries raw native message numbers. Add typed tray-icon events. A backend
translates `WM_*`, X11, or Wayland data once; application code never switches on it.

- Related: T-333, T-306

### T-333 — Application messages expose native event numbers

Add a platform-neutral application-message event with an owned payload and documented dispatch
lifetime, independent of tray interaction.

- Related: T-110, T-292, T-306

### T-292 — Application-to-application messaging has no portable contract

Give single-instance/application messaging a portable contract. The Windows backend may keep
  `FindWindow`/`SendMessage`; another backend may use a local socket or bus. The public identifier,
  payload, delivery, timeout, and failure semantics must be the same.

- Related: T-110

### T-293 — System-icon retrieval and caching are coupled in native GUI code

Split `Application`'s system-icon code into a native operation that obtains one image and common
  Swag that caches it, resizes it, appends it to an atlas, and returns a GUI `Icon`. Do the same for
  each cache consumer without making unrelated shell behavior part of this entry.

- Related: T-294, T-295

### T-294 — Generic offscreen `surfaceAt` behavior remains platform-specific

Move the generic offscreen branch of `surfaceAt` into common GUI code; leave only desktop hit
testing in the backend.

- Related: T-293, T-297

### T-295 — Hot-key command dispatch remains platform-specific

Keep hot-key registration and key-code translation native, but move command lookup and dispatch
into common code.

- Related: T-110

### T-296 — Clipboard image conversion can grow backend-specific codecs

Keep native clipboard files limited to ownership protocols and platform formats; use Pixel codecs
for image conversion rather than growing a decoder in each backend.

- Related: T-287, T-320, T-330

### T-330 — Drag image conversion can grow backend-specific codecs

Route drag/drop image conversion through Pixel independently of clipboard ownership and formats.

- Related: T-039, T-287, T-296

### T-297 — Portable surface policy remains in native leaves

Keep `Surface` position clamping, headless fallbacks, state updates, and command posting common.
  A native surface backend should only create/destroy/show/move the host window, translate input
  and window-manager events, manage clipboard/drag/drop/tray integration, and expose an opaque
  renderer handle.

- Related: T-045, T-110, T-294

### T-111 — Audio's common types import Windows declarations

Delete the unused `Win32` imports from `bus.swg` and `voice.swg`.

- Related: T-331, T-332

### T-331 — WAVE extensible formats use `Win32.GUID`

Represent WAVE extensible GUIDs with a portable packed UUID value.

- Related: T-111, T-332

### T-332 — Audio's WAVE channel mask is named as a native handle

Name and type the field as the WAVE speaker mask it represents, independently of the GUID cleanup.

- Related: T-111, T-331

### T-298 — Audio backend selection is repeated compile-time dispatch

Replace the repeated `#os == Windows` dispatch in `driver/backend.swg` with a backend interface or
  operation table. Driver selection, validation, voice/bus lifecycle, streaming-buffer rotation,
  gain conversion, state transitions, and codec work stay common; XAudio2 is one implementation.

- Related: T-066, T-111, T-299

### T-299 — The no-sound backend is not the explicit portable fallback contract

Keep the no-sound backend available on every target and add the Linux backend under T-066 without
  changing `SoundFile`, `Voice`, or `Bus`. A build that explicitly selects XAudio2 on Linux should
  fail as an unavailable optional backend, not make the Audio module itself Windows-dependent.

- Related: T-066, T-298

### T-112 — Gamepad normalization remains in the native backend

Make a native backend return one raw portable snapshot, then normalize stick/trigger
  ranges, map buttons, apply hysteresis thresholds, and derive directional pseudo-buttons in common
  Swag. XInput vibration and connection errors remain native.

- Related: T-141

### T-300 — Thread lifecycle orchestration remains in the native backend

Keep context cloning, temporary-allocator setup/release, user-lambda dispatch,
  cooperative-stop state, handle ownership, and wait-many orchestration common. Backends create,
  start, join, yield, sleep, identify, and set priority. Account for the current create-suspended
  contract explicitly because POSIX does not provide it directly.

- Related: T-133

### T-301 — Timer scheduling policy remains in the native backend

Implement lifecycle, periodic rescheduling, callback/context dispatch, and cancellation
  races once in Swag over a small monotonic-wait/wake primitive or a common scheduler. Do not clone
  Windows timer-queue policy into every backend.

- Related: T-134

### T-302 — Portable time conversion remains in the native backend

Keep `Timestamp.utcNow = Timestamp.fromDateTime(DateTime.utcNow())` and native-structure to
  `DateTime` field assignment common; backends provide wall-clock fields and monotonic ticks.

- Related: T-134

### T-303 — Console formatting remains in the native backend

Keep null/silent handling and variadic formatting in common Swag, then send bytes through
  a native stdout writer. Color selection, terminal capability, prompting and encoding remain host
  concerns.

- Related: T-139

### T-304 — Cryptographic-random fill policy remains in the native backend

Keep request chunking and fill-completely/retry policy common over one
  OS random-fill primitive. Secure clearing stays governed by T-105.

- Related: T-105, T-273

### T-113 — Unsuffixed sCapture files carry unused native imports

Remove the unused Win32/GDI imports from sCapture's unsuffixed `capturerectwnd.swg` and
`inplaceeditwnd.swg`.

- Related: T-305, T-306, T-308

### T-305 — sCapture's DPI-awareness scope is outside its native backend

Move the DPI-awareness scope in unsuffixed `screenshot.swg` into the Windows capture backend.

- Related: T-084, T-113

### T-306 — sCapture switches on native window messages

Replace sCapture's `WM_USER`, `WM_LBUTTONDBLCLK`, and `WM_RBUTTONDOWN` branches with the tray and
application-message events from T-110. Keep capture/editor policy common.

- Related: T-084, T-110

### T-307 — sCrypt exposes a Windows drive-letter mount destination

Move sCrypt's available-drive-letter query and every WinFsp/registry/guardian concern under its
Windows mount backend. The application chooses an abstract mount destination and consumes mount
status; Linux and macOS backends map it to their native mount points.

- Related: T-100, T-265, T-284

### T-308 — Shipped applications have no native-import boundary check

Reject raw OS imports and native-constant comparisons outside named application backends and
platform integration tests.

- Related: T-103, T-113, T-306, T-307

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
