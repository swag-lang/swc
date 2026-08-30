# Operating-System Portability Backlog

This is the sole backlog for porting any part of Swag to another operating system. It covers
`bin/runtime`, standard modules, shipped applications, compiler tooling, target ABIs, packaging,
and desktop integration for Linux, macOS, and future hosts.

It also owns every Windows-specific type, protocol, service, policy, or assumption that portable
code must stop exposing. The owning module still implements the change, but the entry stays here
with its target backends and prerequisites so one port cannot be scattered across domain files.

The checked dependency layers and their path ownership are defined in
[bin/PORTABILITY.md](../bin/PORTABILITY.md).

Raw interoperability modules such as `win32`, `gdi32`, `gdiplus`, `xinput`, and `xaudio2` are
not themselves portability debt. Explicit adapters such as `Image.from(HBITMAP)` may remain
Windows-only. The debt begins when portable code or a cross-platform product must mention their
types, constants, message numbers, calling conventions, or service behavior.

As of 2026-08-22, the platform-specific body, excluding OpenGL and raw binding modules, is large
enough to justify one coordinated campaign:

| Area | Platform files | Lines |
| --- | ---: | ---: |
| `bin/runtime/os_windows.swg` | 1 | 426 |
| `std/core` (`.win32.swg` and `.xinput.swg`) | 29 | 3,050 |
| `std/gui` (`.win32.swg`, excluding tests) | 5 | 2,967 |
| `std/pixel` (`.win32.swg`, excluding OpenGL and tests) | 3 | 399 |
| `std/audio` XAudio2 backend | 1 | 504 |
| Swag Capture | 1 | 308 |
| Swag Vault, including its platform integration test | 11 | 2,454 |

Those numbers are an inventory, not a deletion target. A small native backend is healthy. The
target is that code above it compiles and is tested without importing a native binding, and that a
new platform implements capabilities rather than copies policy.

---

## Tier A — Portability inventory and build configuration

### platform.portability.001 — No build-only non-Windows portability configuration

Prove the boundary with a build-only non-Windows configuration as early as possible. It may use
  no-sound and headless implementations at first, but it must compile every platform-neutral file.

### platform.portability.002 — Portability progress has no capability inventory

Track both native source lines and, more importantly, native capabilities a new backend must
  implement. Moving 200 lines of orchestration to common Swag is valuable; compressing 200 required
  system calls into a clever wrapper is not.

- Related: platform.portability.001

## Tier A — Runtime host and memory boundary

### platform.portability.003 — Define a minimal runtime host ABI

`bin/runtime/os_windows.swg` combines raw calls with portable policy. Define a minimal host ABI for
thread storage, context/address capture, image/debug-section access, byte output, library loading,
and process termination; keep only those irreducible operations in the Windows leaf.

- Related: platform.portability.004, platform.portability.005

### platform.portability.004 — Linux page-allocation primitives do not exist

The present non-Windows allocator fallbacks are not equivalent: `Swag.alloc` cannot model reserved
  address space, decommitment, or a guard page, while the counters pretend commit/decommit occurred.
  Implement `mmap`/protection/release semantics and thread-exit
  cleanup exist.

- Related: platform.portability.047

### platform.portability.005 — Runtime startup cannot accept an argument vector

Give startup a host ABI that can accept an argument vector directly. Windows may continue to
  parse its process command line, while a Unix entry point supplies `argc`/`argv`; the rest of the
  runtime must see the same `Swag.args()` contract.

- Related: platform.portability.003, platform.portability.008, platform.portability.010

### platform.portability.006 — `Crypto.secureClear` has no no-elide primitive

Make `Crypto.secureClear` a no-elide runtime/compiler primitive or a narrow host primitive. A
  plain Swag loop is not a security guarantee if dead-store elimination may erase it.

- Related: platform.portability.075

### platform.portability.007 — Hosted runtime library dependencies have no target matrix

Record a target matrix for hosted builds: Windows UCRT, Linux libc plus libm where required, and
  any future freestanding runtime. A Linux port is not improved by replacing a stable libc call
  with direct kernel syscalls and thereby coupling the runtime to one kernel and architecture.

- Related: platform.portability.031

## Tier A — Process launch and orchestration

### platform.portability.008 — Make process launch argv-first

- `StartInfo.arguments` is one already-quoted string, which makes Windows command-line quoting the
  public contract. Make an argument slice the normal API. Windows alone serializes it with the
  backslash-before-quote rules; Unix passes the vector unchanged. Keep a clearly named raw native
  command-line escape hatch only if an actual caller needs it.

### platform.portability.009 — Process orchestration remains in the Windows backend

Move the portable parts of `process.win32.swg` out of the backend: stream-redirection policy,
  ownership and cleanup order, output/error accumulation, draining both pipes while waiting,
  timeout loops, cached exit status, and the convenience `startProcess`/`runProcess` families.
  The host leaf should spawn, poll/wait, terminate, and read/write/close one native endpoint.

- Related: platform.portability.032, platform.portability.008, platform.portability.011

### platform.portability.010 — Early argument lookup reparses the Windows command line

Make `Env.findRunArgument` search the runtime argument vector even during early initialization.
  Its portable name/value matching is currently trapped in `sandbox.win32.swg` only because it
  reparses `GetCommandLineA` before `Swag.args()` is populated.

- Related: platform.portability.005, platform.portability.008

### platform.portability.011 — Process-tree resource accounting has no portable capability contract

Preserve the stronger resource contract deliberately. Windows Job Objects account a process
  tree; a Linux implementation needs an explicit process-group/cgroup strategy or must report that
  the capability is unavailable rather than silently measuring only the first child.

- Related: platform.portability.032, platform.portability.009

## Tier A — Filesystem and path conformance

### platform.portability.012 — Filesystems have no cross-host conformance suite

Add filesystem conformance tests on each host for Unicode names, links, permissions, partial I/O,
and recursive traversal.

- Related: platform.portability.033, platform.portability.013

### platform.portability.013 — Paths have no target-independent lexical conformance suite

Test root forms, case policy, trailing separators, dot segments, invalid names, and normalization
without touching the filesystem.

- Related: platform.portability.012

---

## Tier B — Portable desktop service boundaries

### platform.portability.014 — Optional Windows interop is mixed into portable types

Keep `Pixel.Image` conversions to `HICON`/`HBITMAP`, `Gui.Surface.win32Handle`, and keyboard
  virtual-key conversion as optional Windows interop, not methods required of every target.
  Portable callers should use images, opaque render handles, `Input.Key`, and normalized events.

### platform.portability.015 — Desktop actions and application registration share one environment API

Separate generic desktop actions (`openUrl`, reveal a path, enumerate monitors, locale, special
  directories) from platform registration (`registerApplication`, file associations, native
  window creation). Registration belongs in an application-integration module with an explicit
  capability/failure contract, not in the portable core environment namespace.

- Related: platform.portability.038

## Tier B — Installed-font discovery

### platform.portability.016 — Replace the native installed-font descriptor

- `SystemFontFaceInfo` currently stores `LOGFONTW`, so Pixel's public system-font model is a Windows
  descriptor. Replace it with family/subfamily names, normalized style properties, file path, and
  face index. The platform hook should enumerate font files or configured font directories, not
  manufacture a native font handle.

### platform.portability.017 — Installed-font scanning is not common Swag

Use the existing TrueType/OpenType readers (`Face.countFaces`, `familyNameAt`, style/name tables,
  and `Face.loadAt`) to scan configured files and collections into portable face descriptors.

- Related: platform.portability.016, platform.portability.019, platform.portability.020, platform.portability.018

### platform.portability.018 — Installed-font family grouping is not common Swag

Group scanned descriptors into families, select regular/bold/italic fallbacks, sort, and cache the
catalog independently of platform enumeration.

- Related: platform.portability.016, platform.portability.017

### platform.portability.019 — A system face cannot load directly from file and face index

Load `TypeFace` from bytes or a file plus face index. Keep the GDI handle path only as a Windows
  compatibility adapter; it must no longer be the only route from a system family to a face.

- Related: platform.portability.067, platform.portability.016, platform.portability.017

### platform.portability.020 — Linux has no installed-font source

A first Linux backend may provide conventional directories. Fontconfig can be added later for
  aliases, user configuration and substitutions without making basic parsing and grouping depend
  on it.

- Related: platform.portability.017

## Tier B — Application messaging

### platform.portability.021 — Application-message payloads have no ownership contract

Application-message identifiers are platform-neutral, but the event still carries one borrowed
integer parameter. Give messages an owned payload and document its dispatch lifetime independently
of tray interaction.

- Related: platform.portability.022

### platform.portability.022 — Application-to-application messaging has no portable contract

Give single-instance/application messaging a portable contract. The Windows backend may keep
  `FindWindow`/`SendMessage`; another backend may use a local socket or bus. The public identifier,
  payload, delivery, timeout, and failure semantics must be the same.

## Tier B — Portable image and surface policy

### platform.portability.023 — System-icon retrieval and caching are coupled in native GUI code

Split `Application`'s system-icon code into a native operation that obtains one image and common
  Swag that caches it, resizes it, appends it to an atlas, and returns a GUI `Icon`. Do the same for
  each cache consumer without making unrelated shell behavior part of this entry.

### platform.portability.024 — Clipboard image conversion can grow backend-specific codecs

Keep native clipboard files limited to ownership protocols and platform formats; use Pixel codecs
for image conversion rather than growing a decoder in each backend.

- Related: platform.portability.014, platform.portability.055, platform.portability.025

### platform.portability.025 — Drag image conversion can grow backend-specific codecs

Route drag/drop image conversion through Pixel independently of clipboard ownership and formats.

- Related: platform.portability.014, platform.portability.024

### platform.portability.026 — Portable surface policy remains in native leaves

Keep `Surface` position clamping, headless fallbacks, state updates, and command posting common.
  A native surface backend should only create/destroy/show/move the host window, translate input
  and window-manager events, manage clipboard/drag/drop/tray integration, and expose an opaque
  renderer handle.

- Related: platform.portability.050

## Tier B — Backend selection and scheduling

### platform.portability.027 — Audio backend selection is repeated compile-time dispatch

Replace the repeated `#os == Windows` dispatch in `driver/backend.swg` with a backend interface or
  operation table. Driver selection, validation, voice/bus lifecycle, streaming-buffer rotation,
  gain conversion, state transitions, and codec work stay common; XAudio2 is one implementation.

- Related: platform.portability.065, platform.portability.028

### platform.portability.028 — The no-sound backend is not the explicit portable fallback contract

Keep the no-sound backend available on every target and add the Linux backend under platform.portability.065 without
  changing `SoundFile`, `Voice`, or `Bus`. A build that explicitly selects XAudio2 on Linux should
  fail as an unavailable optional backend, not make the Audio module itself Windows-dependent.

- Related: platform.portability.065, platform.portability.027

### platform.portability.029 — Timer scheduling policy remains in the native backend

Implement lifecycle, periodic rescheduling, callback/context dispatch, and cancellation
  races once in Swag over a small monotonic-wait/wake primitive or a common scheduler. Do not clone
  Windows timer-queue policy into every backend.

- Related: platform.portability.036

## Tier B — Application portability enforcement

### platform.portability.030 — Shipped applications have no native-import boundary check

Reject raw OS imports and native-constant comparisons outside named application backends and
platform integration tests.

---

## Tier C — Optional ownership, not a Linux prerequisite

### platform.portability.031 — Decide deliberately whether Swag should ship its own libm

`Swag.sin`, `Swag.cos`, `Swag.tan`, the hyperbolic and inverse functions, `Swag.atan2`, `Swag.log`, `Swag.log2`, `Swag.log10`,
`Swag.exp`, `Swag.exp2`, and `Swag.pow` are language intrinsics but their runtime implementation currently
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


---

The following entries implement the target backends and remove the Windows-bound behavior exposed
by portable modules and products. The earlier entries prepare and enforce the same boundaries.

## Runtime and Core operating-system services

### platform.portability.032 — Process services have no second-platform backend

Add process creation, waiting, termination, pipes, exit status, and resource semantics for the
chosen second platform. The common-policy extraction is tracked separately in platform.portability.008 and platform.portability.009.

- Related: platform.portability.008, platform.portability.009, platform.portability.011

### platform.portability.033 — Filesystem services have no second-platform backend

Implement directory, file, stream, metadata, path-state, and mutation primitives for the chosen
second platform behind the existing common orchestration and path contracts.

### platform.portability.034 — Threads have no second-platform backend

Implement thread creation, start, join, yield, sleep, identity, and priority for the chosen second
platform without copying common lifecycle policy into the native leaf.

- Related: platform.portability.035

### platform.portability.035 — Synchronization primitives have no second-platform backend

Implement mutexes, read-write locks, and events for the chosen second platform behind the existing
portable contracts.

- Related: platform.portability.034, std.core.027

### platform.portability.036 — Clocks have no second-platform backend

Implement wall-clock fields and monotonic ticks for the chosen second platform.

- Related: platform.portability.037

### platform.portability.037 — Timers have no second-platform backend

Implement native timer wait/wake mechanisms for the chosen second platform behind the common
scheduler in platform.portability.029.

- Related: platform.portability.036, platform.portability.029

### platform.portability.038 — Environment services have no second-platform backend

Implement environment variables, arguments, locale, special directories, and generic desktop
actions for the chosen second platform.

- Related: platform.portability.005, platform.portability.010, platform.portability.015

### platform.portability.039 — Native errors have no second-platform mapping

Map the second platform's error domain into the portable `core` failure contract, preserving native
detail without leaking native codes into portable callers.

### platform.portability.040 — The sandbox has no second-platform backend

Implement the sandbox's platform enforcement and early-startup behavior for the chosen second
platform independently of general environment services.

- Related: platform.portability.038, platform.portability.010

### platform.portability.041 — Hardware discovery has no second-platform backend

Implement the portable CPU, memory, display-adjacent, and machine capability queries currently
provided only by Windows.

### platform.portability.042 — Console I/O has no second-platform backend

Implement terminal encoding, capability, color, prompt, and byte output for the chosen second
platform behind the existing common formatting layer.

### platform.portability.043 — Stack capture has no second-platform backend

Provide address capture and current-image discovery for the chosen second platform behind the
runtime host boundary.

- Related: platform.portability.003, platform.portability.045, platform.portability.044

### platform.portability.044 — Debug-symbol access has no second-platform backend

Locate and read the target's debug information for captured addresses, leaving parsing and
presentation in the existing common layer.

- Related: platform.portability.043

### platform.portability.045 — Debugger integration has no second-platform backend

Implement debugger detection, break/attach behavior, and any debugger-facing host operations
independently of stack-symbol presentation.

- Related: platform.portability.003, platform.portability.043

### platform.portability.046 — Input devices have no second-platform backend

Implement keyboard and gamepad acquisition for the chosen second platform while keeping normalized
state and policy in common code.

### platform.portability.047 — The page allocator has no real second-platform OS primitives

Implement equivalents of `allocatorOsCommit`, `allocatorOsDecommit`, page protection, release, and
thread-exit cleanup before enabling the page path on another target. The compiled fallbacks are
placeholders, not an implementation.

- Related: runtime.allocator.008, platform.portability.004

## GUI contracts and operating-system integrations

### platform.portability.048 — Accessibility has no portable semantic tree or Windows adapter

- Problem: `WM_GETOBJECT` is not handled anywhere in the module. That single message is how
  Windows asks an application to describe itself to assistive technology. Without it there is no
  UI Automation provider, no MSAA, and no accessible tree of any kind.
- Consequence: **no screen reader can see a Swag application.** Not partially — at all. Narrator,
  NVDA and JAWS receive nothing. Keyboard-only navigation exists, but nothing announces what has
  focus.
- This is also a procurement and legal question, not only an ethical one. The European
  Accessibility Act has applied since June 2025 and US Section 508 governs federal purchasing. Qt,
  GTK, WinUI, Avalonia, Flutter and Slint all implement this, and egui added it through AccessKit
  precisely because its absence was disqualifying.
- Next: define a platform-neutral accessible tree with roles, names, values, states, focus, and
  actions, validate it through the headless host, then expose it through a Windows UI Automation
  provider rooted at the surface. No portable widget or event may mention UIA or a native message.
- Complete when: Narrator, NVDA, and JAWS can inspect and operate the first supported controls on
  Windows, the semantic tree is backend-independent, and platform.portability.060 can map another OS without changing
  widget APIs.
- This is the single most important entry in any of the five module backlogs.

### platform.portability.049 — Text composition has no portable contract or Windows IME adapter

- Problem: no `WM_IME_STARTCOMPOSITION`, `WM_IME_COMPOSITION`, `WM_IME_ENDCOMPOSITION`,
  `WM_IME_SETCONTEXT` or `WM_IME_NOTIFY`. Text input is `WM_CHAR` and `WM_KEYDOWN` only.
- Consequence: **Chinese, Japanese and Korean text cannot be typed** into an `EditBox`, a
  `PasswordEdit`, or the rich editor. Nor can Vietnamese or any other input relying on composition.
  This is not degraded input; it does not work.
- Next: define backend-neutral composition start/update/commit/cancel events, clause styling, and
  candidate-window geometry, then translate the Windows IME messages into that model. The caret
  geometry needed for placement already exists in `EditBox`.
- Complete when: Chinese, Japanese, Korean, and Vietnamese composition works on Windows, headless
  tests cover the common model, and platform.portability.061 can add another OS without changing editor APIs.

### platform.portability.050 — No second-platform surface and presentation backend

Inherited from [platform.portability.032](#platformportability032--process-services-have-no-second-platform-backend), and gated by it.
The filenames already expose most of the seam: `surface.win32.swg`, `application.win32.swg`,
`clipboard.win32.swg`, `dragdrop.win32.swg` and `cursor.win32.swg`. The retained tree, layouts,
themes, controls and the toolkit-owned file dialog are platform-neutral. That is a good boundary,
but five replacement files are not yet a porting plan.

Choose one platform and implement the application loop, surface creation/destruction, native
resize/move/minimize, renderer presentation, and cursor as the first independently testable slice.

- Related: platform.portability.051, platform.portability.057, platform.portability.060

### platform.portability.051 — No second-platform monitor and DPI integration

Implement monitor enumeration and per-monitor scale for the platform whose surface exists under
platform.portability.050.

- Related: platform.portability.050, std.gui.007, platform.portability.052, platform.portability.055, platform.portability.056

### platform.portability.052 — No second-platform keyboard routing

Translate native key identity, modifier, repeat, and layout state into the portable keyboard
events.

- Related: platform.portability.050, std.gui.008, platform.portability.053, platform.portability.054

### platform.portability.053 — No second-platform text-input routing

Translate committed native text input into the portable text event independently of IME
composition.

- Related: platform.portability.049, platform.portability.052, platform.portability.061

### platform.portability.054 — No second-platform pointer routing

Translate mouse, touch, and pen input into the portable pointer contract.

- Related: std.gui.011, platform.portability.052

### platform.portability.055 — No second-platform clipboard integration

Implement clipboard ownership and platform-format conversion behind the portable typed-value
contract.

- Related: platform.portability.050, platform.portability.024

### platform.portability.056 — No second-platform system-theme notifications

Translate the platform's live theme and high-contrast changes into the portable settings event.

- Related: std.gui.005, platform.portability.050, std.gui.006

### platform.portability.057 — No second-platform GUI packaging

Package the GUI runtime and native dependencies for the chosen second platform.

- Related: platform.portability.050, platform.portability.058, platform.portability.059

### platform.portability.058 — No second-platform GUI font integration

Connect GUI font selection and fallback to the installed-font catalog for the chosen platform.

- Related: platform.portability.016, platform.portability.057

### platform.portability.059 — No second-platform file-dialog integration

Connect the toolkit-owned file dialog to the target filesystem and native path expectations.

- Related: platform.portability.033, platform.portability.057

### platform.portability.060 — Accessibility has no second-platform integration

Map the platform's native assistive-technology service to the accessibility contract from platform.portability.048.

- Related: platform.portability.048, platform.portability.050, platform.portability.061, platform.portability.062

### platform.portability.061 — IME has no second-platform integration

Map the platform's composition and candidate-window service to the input-method contract from
platform.portability.049.

- Related: platform.portability.049, platform.portability.050

### platform.portability.062 — Drag and drop has no second-platform integration

Map the platform's data-transfer and gesture service to the drag and drop contract the Win32
backend already implements.

- Related: platform.portability.050

Platform-neutral events must not expose native message numbers, and the Win32 backend should keep
passing its existing tests throughout the extraction. The headless backend remains the contract
test; backend integration tests then prove native focus, DPI, clipboard and input on each system.
platform.portability.050 is complete when a non-trivial GUI sample opens, lays out, paints, resizes, and closes on the
second platform. The higher integrations retain their own completion identifiers.

This only removes the interface blocker for the applications. Swag Capture still needs its separate
capture backend in [platform.portability.071](#platformportability071--cross-platform-capture-backend); Swag Vault still
needs the FUSE backend in [platform.portability.078](#platformportability078--no-linux-fuse-backend), plus the
Core and Pixel platform work under platform.portability.032. Keeping those dependencies explicit prevents a GUI port
from being mistaken for two ported products.

## Audio, graphics, and capture operating-system boundaries

### platform.portability.063 — Spatialization is coupled to an unused X3DAudio handle

- `src/driver/xaudio2.swg` calls `X3DAudioInitialize` and stores the handle in `x3DInstance`. That
  handle is never read again. The 3D engine is initialized on every engine creation and does
  nothing.
- Next: define portable listener, source-position, distance-attenuation, and channel-matrix
  semantics, then lower them through X3DAudio in the Windows backend. Other backends may use their
  native spatializer or an explicitly supported common fallback.
- Complete when: the public model contains no X3DAudio types, the Windows matrix is validated, and
  a backend can declare or implement the same capability without changing `Voice`.
- Related: std.audio.007

### platform.portability.064 — Voice filters are specified only by XAudio2 capabilities

- Submix voices are created with `XAUDIO2_VOICE_USEFILTER` in `src/driver/xaudio2.swg`. The
  capability is requested and no API exposes it.
- XAudio2 gives a per-voice low-pass, high-pass, band-pass and notch filter once that flag is set.
- Next: specify portable filter kinds, cutoff, resonance, update timing, and unsupported-capability
  behavior on `Voice` and `Bus`, then map the first implementation to XAudio2.
- Complete when: no public filter contract names XAudio2, Windows uses its native filters, and a
  second backend can implement or reject the same operation explicitly.
- Related: std.audio.008, std.audio.009, std.audio.014

### platform.portability.065 — Audio has no real non-Windows backend

- `DriverKind` is `Default`, `NoSound`, `XAudio2`. Off Windows, `Default` resolves to silence.
- The backend boundary in `src/driver/backend.swg` is clean and already has two implementations, so
  a third is additive rather than structural. CoreAudio and ALSA or PulseAudio are the obvious
  targets; WASAPI directly would also remove the XAudio2 dependency on Windows.
- Complete when: one chosen non-Windows target opens a real output device and passes the common
  engine, voice, bus, streaming, and device-lifecycle contract while `NoSound` remains explicit.

### platform.portability.066 — Renderer backend choice has no target matrix

- `render/` has `cpu` and `ogl`. There is no Vulkan, Direct3D, Metal or WebGPU path.
- On Windows this is the weakest choice available: OpenGL driver quality varies widely, and some
  ARM devices have no usable implementation at all. Skia ships GL, Vulkan, Metal and D3D.
- This also intersects platform.portability.032. Choose the next renderer from the operating systems and hardware the
  project intends to ship, rather than adding a backend independently of the port plan.
- The backend boundary is already two implementations deep, so a third is additive.
- Complete when: the supported OS/GPU matrix names the default and fallback renderer for each
  target, and the next required backend presents through the portable surface contract.

### platform.portability.067 — A collection face is selected by name, and a localized Windows will miss

`TypeFace.createFromHfont` now asks GDI for the `ttcf` table, and picks the face out of the
collection by matching the family GDI enumerated against `Face.familyNameAt`. That match is between
the name Windows reports for the current locale and the best-scoring `name` record in the face,
which this module scores towards English. Where they disagree the match fails and face zero is
taken, which is a wrong family rather than a refusal.

Verified on a French Windows 11: all twelve collection-backed families — `MS Gothic`, `MS PGothic`,
`MS UI Gothic`, `Cambria`, `Cambria Math`, `SimSun`, `NSimSun`, `Yu Gothic`, `Nirmala UI`,
`Nirmala Text`, `Microsoft JhengHei`, `Microsoft YaHei` — resolve to their own face and render.
A Japanese or Chinese Windows enumerates `ＭＳ ゴシック` and `宋体` instead, and has not been tried.

The bounded fix is to match against every `name` record a face declares rather than only the
best-scoring one, which needs `truetype` to answer "does this face call itself X" rather than
"what is this face called". Weigh that against reading the face index out of the offset tables
instead, which is locale-proof but needs the synthesized single-face file as well as the
collection, and so reads the font twice.

- Complete when: the Windows adapter returns the portable file-and-face-index descriptor from
  platform.portability.016/platform.portability.019 without locale-dependent matching, and the same descriptor accepts platform.portability.020's source.

### platform.portability.068 — Capture clipboard files are specified as OLE data

- Evidence: a capture leaves as a file, bitmap clipboard data, or an outgoing drag, but cannot be
  copied as a virtual file. The obvious current implementation reuses `DragData` through
  `OleSetClipboard`, which would make OLE the application contract.
- Next: add the virtual-file descriptor and deferred contents to std.gui.001's portable typed clipboard,
  then map them to OLE only in the Windows backend.
- Complete when: paste targets receive the file and bitmap media on Windows, while Swag Capture
  calls no OLE API and another clipboard backend can publish the same virtual file.
- Related: app.capture.001, std.gui.001

### platform.portability.069 — Capture OCR is specified as a Windows-only service

- Problem: no text recognition anywhere in the module. The Windows Snipping Tool has it, Snagit
  has it, ShareX has it. It has gone from a differentiator to an expectation.
- Next: define an OCR provider contract over a pixel selection, bind the Windows OS engine as the
  first provider, and keep provider availability explicit so another OS can use its native service
  or an optional local engine without changing the command.
- Complete when: the command returns text through the provider on Windows, absence is reported
  honestly, and capture/editor code imports no Windows OCR type.
- Why this high: it is the most visible remaining reason to reach for the built-in tool instead of
  this one, and the platform does the hard part.

### platform.portability.070 — Scrolling capture has no portable scroll-driving backend

- Snagit's most-cited feature; ShareX has it too. Capture a window taller or wider than the screen
  by scrolling it and stitching the frames.
- Cost: real. Windows can drive scrolling through UI Automation or synthesized messages, while
  other window systems expose different capabilities. Keep overlap detection and frame stitching
  common, and put window discovery, scroll requests, bounds, and refusal in a native backend.
- Sequence it after Tier A, and scope it to the common cases — a browser page, a document, a list
  view — rather than promising it works everywhere.
- Complete when: the common stitcher consumes backend-neutral frames and scroll results, the
  Windows backend covers the stated common cases, and unsupported targets fail explicitly.

### platform.portability.071 — Cross-platform capture backend

`src/screenshot/screenshot.win32.swg` and the GDI dependency are the whole platform boundary on the
capture side. The editor, the forms, the library, and the serialization are already portable.

- Complete when: one chosen non-Windows backend captures the supported screen/window/region set and
  the application imports no raw OS binding outside named capture backends.

## Application, shell, and release integrations

### platform.portability.072 — Swag Scope has no portable preview-provider boundary

- Intent: the shipped viewers are reachable from where a file is selected. This is the whole reason
  QuickLook won its category: select, look, move on, without launching an application.
- Next: define an out-of-process-safe preview request/result contract, then host it in an Explorer
  preview handler as the first OS adapter.
- Complete when: Explorer renders the same supported views through `--register-file-types`, the
  application window is not required, and another desktop preview service can host the contract.
- Note: the handler hosts a view in a process it does not own, so the viewer request/result contract
  has to be usable without the application window. That constraint is worth checking before committing.
- Related: platform.portability.073, platform.portability.074

### platform.portability.073 — Swag Scope has no portable thumbnail-provider boundary

- Intent: the image, SVG, and Markdown views can produce a representative bitmap; Explorer asks for
  one and gets nothing.
- Next: define a bounded thumbnail request over the common viewer renderer, then implement the
  Windows Explorer provider without exposing its COM types to viewer code.
- Complete when: registered formats produce bounded thumbnails on Windows and another desktop
  thumbnail service can consume the same renderer contract.
- Related: platform.portability.072

### platform.portability.074 — File-type registration is Windows-only

- Intent: `Env.registerApplication`, `Env.associateFileExtension`, and the shell integration entries
  above are the whole platform boundary; the viewers, streaming, and structure readers are portable.
- Complete when: desktop registration goes through whatever portable contract platform.portability.015 settles on.
- Related: platform.portability.001, platform.portability.015

### platform.portability.075 — Keys live in pageable memory

- Owner: `bin/std` for the locked allocation, Swag Vault for the policy
- Problem: `Crypto.Keys` and the unwrapped master key are ordinary memory. The page file or a crash
  minidump can capture the master key. VeraCrypt locks its key pages.
- Next: define a locked-memory allocation with explicit availability/failure semantics, implement
  it with each target's page-locking primitive, and require Swag Vault's unwrapped keys to use it.
  Keep dump exclusion and lifecycle wiping independently testable.
- Complete when: supported targets prove the key pages are locked or refuse securely, and Vault
  contains no direct `VirtualLock`, `mlock`, or equivalent call.
- Related: platform.portability.076

### platform.portability.076 — Crash-dump exclusion has only a Windows-specific design

- Owner: Swag Vault
- Define the portable security capability and its unsupported behavior, register key regions with
  Windows Error Reporting as the first backend, and verify the configured dump policy. Add target
  adapters only where the OS offers an enforceable equivalent.
- Related: platform.portability.075

### platform.portability.077 — Release signing and elevation policy are Windows-only

- Owner: release process
- Problem: the application requests UAC elevation to start the driver. Unsigned, the consent dialog
  reads "Unknown publisher" for an encryption tool. This is a larger adoption obstacle than any
  feature on this list.
- Next: define signing, verification, elevation, and packaging requirements per shipped target.
  Apply an OV or EV certificate to `swagvault.exe`; record the corresponding macOS signing and
  notarization contract before that port ships, and state the Linux package policy explicitly.
- Note: elevation is only required because the portable WinFsp driver has to be registered by the
  guardian process. A system-wide WinFsp installation makes `loadWinFsp` take the installed runtime
  and skip the guardian entirely, which is also what allows an automated end-to-end test loop
  without a consent dialog on every run.

### platform.portability.078 — No Linux FUSE backend

- Owner: Swag Vault
- The boundary is already where it needs to be: system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, plus the WinFsp layer and the mount-point selector. Everything above them — the
  container format, the logical filesystem, the password widget — is platform-independent already.
  Real work, no design risk.
- Related: platform.portability.079

### platform.portability.079 — No macOS filesystem backend

- Owner: Swag Vault
- Add the macOS mount backend and packaging independently of Linux, choosing the supported FUSE or
  native filesystem mechanism explicitly.
- Related: platform.portability.078

## Compiler tooling and target ABIs

### platform.portability.080 — Bare `.swgs` execution has only a Windows shell contract

**Evidence.** `tools/setup.swgs` installs the current-user file association used by double-click launch, but its own guidance still requires elevated `assoc`/`ftype` configuration for bare script execution in a shell.

**Intent.** Define shell and desktop-launch integration per host without making Windows file
associations the portable script contract. Machine-wide mutation remains explicit and opt-in.

**Complete when.**

- Setup reports whether bare execution is supported for the current shell and either configures it safely or prints the exact remaining elevated step.
- A fresh `cmd.exe` and Windows PowerShell 5.1 session execute a representative bare `.swgs` script according to that contract.
- A supported non-Windows shell either executes the same representative script through its
  documented launcher/shebang path or reports bare execution as unsupported with an exact command.
- Existing double-click behavior remains intact.
- Moving the checkout and rerunning setup refreshes stale interpreter paths, and removal instructions undo installed associations.

**Related:** compiler.core.016.

### platform.portability.081 — Foreign vector ABIs are unavailable

- Intent: support explicitly selected platform vector ABIs for foreign declarations where the ABI
  is stable, while continuing to reject an ambiguous bare C-vector contract.
- Complete when: supported Windows x64 and one non-Windows target's vector parameters and returns
  interoperate with C/C++ fixtures, unsupported conventions fail semantically, and the contract is
  documented per target.
- Related: cpu.simd.002.
