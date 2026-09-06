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

The following entries implement the target backends and remove the Windows-bound behavior exposed
by portable modules and products. The earlier entries prepare and enforce the same boundaries.

### platform.portability.022 — Application-to-application messaging has no portable contract

- Recorded: 2026-08-09 11:06
- Updated: 2026-09-06 17:42 — git: Add unit tests for float to u64 conversion safety checks

Give single-instance/application messaging a portable contract. The Windows backend may keep
  `FindWindow`/`SendMessage`; another backend may use a local socket or bus. The public identifier,
  payload, delivery, timeout, and failure semantics must be the same.

Swag Scope is a concrete consumer: an association launch currently creates another process.
Forward its requested file to a running instance through this contract, preserving launch failure
reporting and the receiving application's ownership of queued document opens.

- Related: app.scope.001

### platform.portability.048 — Accessibility has no portable semantic tree or Windows adapter

- Recorded: 2026-08-30 12:29
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: the GUI module has no `WM_GETOBJECT` handler, UI Automation provider, MSAA adapter,
  or common accessibility tree. Its custom controls therefore expose no semantic roles, names,
  states, or actions to assistive technology. Existing keyboard navigation supplies no such model.
- Next: define a platform-neutral accessible tree with roles, names, values, states, focus, and
  actions, validate it through the headless host, then expose it through a Windows UI Automation
  provider rooted at the surface. No portable widget or event may mention UIA or a native message.
- Complete when: Narrator, NVDA, and JAWS can inspect and operate the first supported controls on
  Windows, the semantic tree is backend-independent, and platform.portability.060 can map another OS without changing
  widget APIs.

### platform.portability.049 — Text composition has no portable contract or Windows IME adapter

- Recorded: 2026-08-30 12:29
- Updated: 2026-09-06 07:51 — git: prompt 6
- Problem: no `WM_IME_STARTCOMPOSITION`, `WM_IME_COMPOSITION`, `WM_IME_ENDCOMPOSITION`,
  `WM_IME_SETCONTEXT` or `WM_IME_NOTIFY`. Text input is `WM_CHAR` and `WM_KEYDOWN` only.
- Missing behavior: editors have no representation of an active composition, its clauses, or the
  candidate-window location. Receiving committed characters through ordinary text events does
  not prove that composition and candidate selection work correctly.
- Next: define backend-neutral composition start/update/commit/cancel events, clause styling, and
  candidate-window geometry, then translate the Windows IME messages into that model. The caret
  geometry needed for placement already exists in `EditBox`.
- Complete when: Chinese, Japanese, Korean, and Vietnamese composition works on Windows, headless
  tests cover the common model, and platform.portability.061 can add another OS without changing editor APIs.

### platform.portability.004 — Linux page-allocation primitives do not exist

- Recorded: 2026-08-09 11:06
- Updated: 2026-09-06 07:51 — git: prompt 6

The present non-Windows allocator fallbacks are not equivalent: `Swag.alloc` cannot model reserved
  address space, decommitment, or a guard page, while the counters pretend commit/decommit occurred.
  Implement `mmap`/protection/release semantics and thread-exit cleanup before enabling the page
  path on Linux. Cover `allocatorOsCommit`, `allocatorOsDecommit`, protection, and release behind
  the runtime host boundary.

- Related: runtime.allocator.008

### platform.portability.006 — `Crypto.secureClear` has no portable no-elide primitive

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-06 07:51 — git: prompt 6

`crypto/security.win32.swg` already calls the foreign `RtlZeroMemory` routine; the shipped
implementation is no longer a plain Swag loop. Give the same public operation a runtime/compiler
primitive or narrow host implementations on other targets, preserving its no-elide guarantee.

- Related: platform.portability.075

### platform.portability.009 — Process orchestration remains in the Windows backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-06 07:51 — git: prompt 6

The process value, environment map, recorded-status accessors, and convenience
`startProcess`/`runProcess` overloads already live in common `process.swg`. Move the remaining
portable orchestration out of `process.win32.swg`: redirection setup policy, ownership and cleanup
order, output/error accumulation, draining both pipes while waiting, and timeout loops. The host
leaf should spawn, poll/wait, terminate, and read/write/close one native endpoint.

- Related: platform.portability.032, platform.portability.008, platform.portability.011

### platform.portability.013 — Paths have no target-independent lexical conformance suite

- Recorded: 2026-08-09 11:06
- Updated: 2026-09-06 07:51 — git: prompt 6

`core/src/tests/filesystem/path.test.swg` already tests lexical Windows path behavior without
touching the filesystem. Extend that coverage to independent target-policy tables for Windows
and Unix: root forms, case policy, trailing separators, dot segments, invalid names, and
normalization. A host must be able to exercise both policies without running another OS.

- Related: platform.portability.012

### platform.portability.088 — Network transports have no host backends

- Recorded: 2026-08-30 12:27
- Updated: 2026-09-06 07:51 — git: prompt 6
- Owner: the `net` module proposed by std.core.001.
- Evidence: `bin/std/modules` has no `net` module or socket/resolver backend. The TCP entry
  previously mixed its public contract with Winsock and BSD-socket implementation work.
- Next: once the endpoint and ownership contract is chosen, implement Windows and POSIX leaves
  for blocking TCP, UDP, and host/service resolution. Keep native handles and error translation
  inside those leaves; add readiness only after the common concurrency contract is decided.
- Complete when: both host backends pass the same loopback, partial-transfer, cancellation,
  resolution-failure, and handle-lifetime tests without exposing native types to callers.
- Related: std.core.001, std.core.002, std.core.003, std.core.004, language.parallelism.001.

### platform.portability.054 — Native input has no portable mouse, touch, and pen adapter

- Recorded: 2026-08-30 12:27
- Updated: 2026-09-06 07:51 — git: prompt 6

Implement native adapters for the pointer contract in std.gui.011. The current Windows backend
polls mouse state but does not translate `WM_POINTER`, `WM_TOUCH`, or `WM_GESTURE` into contacts.
Add pointer identity, contact lifetime and capture cancellation, suppress duplicate compatibility
mouse events, then map the same contract on the next platform. Keep gesture recognition and
arbitration in the portable GUI layer.

- Related: std.gui.011, platform.portability.052

### platform.portability.051 — No second-platform monitor and DPI integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js

Implement monitor enumeration and per-monitor scale for the platform whose surface exists under
platform.portability.050.

- Related: platform.portability.050, platform.portability.084, platform.portability.052, platform.portability.055, platform.portability.056

### platform.portability.052 — No second-platform keyboard routing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js

Translate native key identity, modifier, repeat, and layout state into the portable keyboard
events.

- Related: platform.portability.050, platform.portability.085, platform.portability.053, platform.portability.054

### platform.portability.056 — No second-platform system-theme notifications

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js

Translate the platform's live theme and high-contrast changes into the portable settings event.

- Related: platform.portability.082, platform.portability.050, platform.portability.083

### platform.portability.081 — Foreign vector ABIs are unavailable

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Intent: support explicitly selected platform vector ABIs for foreign declarations where the ABI
  is stable, while continuing to reject an ambiguous bare C-vector contract.
- Complete when: supported Windows x64 and one non-Windows target's vector parameters and returns
  interoperate with C/C++ fixtures, unsupported conventions fail semantically, and the contract is
  documented per target.
- Related: cpu.simd.002.

### platform.portability.082 — System theme changes are ignored

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` handles `WM_SETTINGCHANGE` only by calling `refreshSystemMotionPreference`; it does not refresh theme policy.

Handle the platform settings-change notification and update live light/dark policy without
restarting the application.

- Related: platform.portability.083

### platform.portability.083 — System high-contrast changes are ignored

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` handles settings changes for reduced motion, but neither that handler nor `application.swg` refreshes high-contrast policy.

Refresh high-contrast policy on the platform settings notification and ensure it overrides visual
theme choices as required for accessibility.

- Related: platform.portability.048, platform.portability.082

### platform.portability.084 — Display-topology changes are ignored

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` has no `WM_DISPLAYCHANGE` route; monitor enumeration is not refreshed from a topology notification.

Refresh monitor enumeration, placement constraints, and dependent application state when a monitor
is added, removed, or rearranged.

- Related: platform.portability.071, platform.portability.051

### platform.portability.085 — Input-language changes are ignored

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` handles key and character messages but has no `WM_INPUTLANGCHANGE` route.

Handle the platform input-language notification and update keyboard-layout-dependent state.

- Related: platform.portability.049

### platform.portability.086 — No printer discovery or native print-job backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Owner: std/gui
- Evidence: `bin/std/modules/gui/src` has no printer enumeration or print-job backend; the portable pagination contract remains std.gui.030.

Enumerate printers and capabilities, open a native job, spool every page from std.gui.030, and report
failure at each stage. Keep one optional virtual-PDF integration test; correctness must
not depend on an installed driver.

- Related: std.gui.030, std.gui.033, std.gui.032

### platform.portability.072 — Swag Scope has no portable preview-provider boundary

- Recorded: 2026-08-30 12:27
- Updated: 2026-09-01 21:15 — git: Refactor backlog entries for improved clarity and detail across document, text, and viewer scopes
- Intent: the shipped viewers are reachable from where a file is selected. This is the whole reason
  Quick Look won its category: select, look, move on, without launching an application.
- Evidence: Apple exposes Quick Look from Finder with Space and adjacent-item navigation. Windows
  preview handlers likewise render a selected file without launching its associated application,
  but add a security constraint Swag Scope must preserve: the handler runs out of process, at low
  integrity by default, and should receive a host-owned stream rather than ambient path authority.
- Next: define an out-of-process-safe preview request/result contract, then host it in an Explorer
  preview handler as the first OS adapter.
- Complete when: Explorer renders the same supported views through `--register-file-types`, the
  application window is not required, a selected file reaches first presentable content within the
  shared preview budget, decoder failure cannot damage Explorer, and another desktop preview service
  can host the contract.
- Note: the handler hosts a view in a process it does not own, so the viewer request/result contract
  has to be usable without the application window. That constraint is worth checking before committing.
- Related: app.scope.viewers.009, app.scope.viewers.011, platform.portability.073,
  platform.portability.074

### platform.portability.001 — No build-only non-Windows portability configuration

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Prove the boundary with a build-only non-Windows configuration as early as possible. It may use
  no-sound and headless implementations at first, but it must compile every platform-neutral file.

### platform.portability.002 — Portability progress has no capability inventory

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Track both native source lines and, more importantly, native capabilities a new backend must
  implement. Moving 200 lines of orchestration to common Swag is valuable; compressing 200 required
  system calls into a clever wrapper is not.

- Related: platform.portability.001

### platform.portability.003 — Define a minimal runtime host ABI

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

`bin/runtime/os_windows.swg` combines raw calls with portable policy. Define a minimal host ABI for
thread storage, context/address capture, image/debug-section access, byte output, library loading,
and process termination; keep only those irreducible operations in the Windows leaf.

- Related: platform.portability.004, platform.portability.005

### platform.portability.005 — Runtime startup cannot accept an argument vector

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Give startup a host ABI that can accept an argument vector directly. Windows may continue to
  parse its process command line, while a Unix entry point supplies `argc`/`argv`; the rest of the
  runtime must see the same `Swag.args()` contract.

- Related: platform.portability.003, platform.portability.008, platform.portability.010

### platform.portability.007 — Hosted runtime library dependencies have no target matrix

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Record a target matrix for hosted builds: Windows UCRT, Linux libc plus libm where required, and
  any future freestanding runtime. A Linux port is not improved by replacing a stable libc call
  with direct kernel syscalls and thereby coupling the runtime to one kernel and architecture.

- Related: platform.portability.031

### platform.portability.008 — Make process launch argv-first

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- `StartInfo.arguments` is one already-quoted string, which makes Windows command-line quoting the
  public contract. Make an argument slice the normal API. Windows alone serializes it with the
  backslash-before-quote rules; Unix passes the vector unchanged. Keep a clearly named raw native
  command-line escape hatch only if an actual caller needs it.

### platform.portability.010 — Early argument lookup reparses the Windows command line

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Make `Env.findRunArgument` search the runtime argument vector even during early initialization.
  Its portable name/value matching is currently trapped in `sandbox.win32.swg` only because it
  reparses `GetCommandLineA` before `Swag.args()` is populated.

- Related: platform.portability.005, platform.portability.008

### platform.portability.011 — Process-tree resource accounting has no portable capability contract

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Preserve the stronger resource contract deliberately. Windows Job Objects account a process
  tree; a Linux implementation needs an explicit process-group/cgroup strategy or must report that
  the capability is unavailable rather than silently measuring only the first child.

- Related: platform.portability.032, platform.portability.009

### platform.portability.012 — Filesystems have no cross-host conformance suite

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add filesystem conformance tests on each host for Unicode names, links, permissions, partial I/O,
and recursive traversal.

- Related: platform.portability.033, platform.portability.013

### platform.portability.014 — Optional Windows interop is mixed into portable types

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Keep `Pixel.Image` conversions to `HICON`/`HBITMAP`, `Gui.Surface.win32Handle`, and keyboard
  virtual-key conversion as optional Windows interop, not methods required of every target.
  Portable callers should use images, opaque render handles, `Input.Key`, and normalized events.

### platform.portability.015 — Desktop actions and application registration share one environment API

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Separate generic desktop actions (`openUrl`, reveal a path, enumerate monitors, locale, special
  directories) from platform registration (`registerApplication`, file associations, native
  window creation). Registration belongs in an application-integration module with an explicit
  capability/failure contract, not in the portable core environment namespace.

- Related: platform.portability.038

### platform.portability.016 — Replace the native installed-font descriptor

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- `SystemFontFaceInfo` currently stores `LOGFONTW`, so Pixel's public system-font model is a Windows
  descriptor. Replace it with family/subfamily names, normalized style properties, file path, and
  face index. The platform hook should enumerate font files or configured font directories, not
  manufacture a native font handle.

### platform.portability.017 — Installed-font scanning is not common Swag

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Use the existing TrueType/OpenType readers (`Face.countFaces`, `familyNameAt`, style/name tables,
  and `Face.loadAt`) to scan configured files and collections into portable face descriptors.

- Related: platform.portability.016, platform.portability.019, platform.portability.020, platform.portability.018

### platform.portability.018 — Installed-font family grouping is not common Swag

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Group scanned descriptors into families, select regular/bold/italic fallbacks, sort, and cache the
catalog independently of platform enumeration.

- Related: platform.portability.016, platform.portability.017

### platform.portability.019 — A system face cannot load directly from file and face index

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Load `TypeFace` from bytes or a file plus face index. Keep the GDI handle path only as a Windows
  compatibility adapter; it must no longer be the only route from a system family to a face.

- Related: platform.portability.067, platform.portability.016, platform.portability.017

### platform.portability.020 — Linux has no installed-font source

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

A first Linux backend may provide conventional directories. Fontconfig can be added later for
  aliases, user configuration and substitutions without making basic parsing and grouping depend
  on it.

- Related: platform.portability.017

### platform.portability.021 — Application-message payloads have no ownership contract

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Application-message identifiers are platform-neutral, but the event still carries one borrowed
integer parameter. Give messages an owned payload and document its dispatch lifetime independently
of tray interaction.

- Related: platform.portability.022

### platform.portability.023 — System-icon retrieval and caching are coupled in native GUI code

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Split `Application`'s system-icon code into a native operation that obtains one image and common
  Swag that caches it, resizes it, appends it to an atlas, and returns a GUI `Icon`. Do the same for
  each cache consumer without making unrelated shell behavior part of this entry.

### platform.portability.024 — Clipboard image conversion can grow backend-specific codecs

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Keep native clipboard files limited to ownership protocols and platform formats; use Pixel codecs
for image conversion rather than growing a decoder in each backend.

- Related: platform.portability.014, platform.portability.055, platform.portability.025

### platform.portability.025 — Drag image conversion can grow backend-specific codecs

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Route drag/drop image conversion through Pixel independently of clipboard ownership and formats.

- Related: platform.portability.014, platform.portability.024

### platform.portability.026 — Portable surface policy remains in native leaves

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Keep `Surface` position clamping, headless fallbacks, state updates, and command posting common.
  A native surface backend should only create/destroy/show/move the host window, translate input
  and window-manager events, manage clipboard/drag/drop/tray integration, and expose an opaque
  renderer handle.

- Related: platform.portability.050

### platform.portability.027 — Audio backend selection is repeated compile-time dispatch

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Replace the repeated `#os == Windows` dispatch in `driver/backend.swg` with a backend interface or
  operation table. Driver selection, validation, voice/bus lifecycle, streaming-buffer rotation,
  gain conversion, state transitions, and codec work stay common; XAudio2 is one implementation.

- Related: platform.portability.065, platform.portability.028

### platform.portability.028 — The no-sound backend is not the explicit portable fallback contract

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Keep the no-sound backend available on every target and add the Linux backend under platform.portability.065 without
  changing `SoundFile`, `Voice`, or `Bus`. A build that explicitly selects XAudio2 on Linux should
  fail as an unavailable optional backend, not make the Audio module itself Windows-dependent.

- Related: platform.portability.065, platform.portability.027

### platform.portability.029 — Timer scheduling policy remains in the native backend

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement lifecycle, periodic rescheduling, callback/context dispatch, and cancellation
  races once in Swag over a small monotonic-wait/wake primitive or a common scheduler. Do not clone
  Windows timer-queue policy into every backend.

- Related: platform.portability.036

### platform.portability.031 — Decide deliberately whether Swag should ship its own libm

- Recorded: 2026-08-09 11:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

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

### platform.portability.032 — Process services have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add process creation, waiting, termination, pipes, exit status, and resource semantics for the
chosen second platform. The common-policy extraction is tracked separately in platform.portability.008 and platform.portability.009.

- Related: platform.portability.008, platform.portability.009, platform.portability.011

### platform.portability.033 — Filesystem services have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement directory, file, stream, metadata, path-state, and mutation primitives for the chosen
second platform behind the existing common orchestration and path contracts.

### platform.portability.034 — Threads have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement thread creation, start, join, yield, sleep, identity, and priority for the chosen second
platform without copying common lifecycle policy into the native leaf.

- Related: platform.portability.035

### platform.portability.035 — Synchronization primitives have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement mutexes, read-write locks, and events for the chosen second platform behind the existing
portable contracts.

- Related: platform.portability.034, std.core.027

### platform.portability.036 — Clocks have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement wall-clock fields and monotonic ticks for the chosen second platform.

- Related: platform.portability.037

### platform.portability.037 — Timers have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement native timer wait/wake mechanisms for the chosen second platform behind the common
scheduler in platform.portability.029.

- Related: platform.portability.036, platform.portability.029

### platform.portability.038 — Environment services have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement environment variables, arguments, locale, special directories, and generic desktop
actions for the chosen second platform.

- Related: platform.portability.005, platform.portability.010, platform.portability.015

### platform.portability.039 — Native errors have no second-platform mapping

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Map the second platform's error domain into the portable `core` failure contract, preserving native
detail without leaking native codes into portable callers.

### platform.portability.040 — The sandbox has no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement the sandbox's platform enforcement and early-startup behavior for the chosen second
platform independently of general environment services.

- Related: platform.portability.038, platform.portability.010

### platform.portability.041 — Hardware discovery has no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement the portable CPU, memory, display-adjacent, and machine capability queries currently
provided only by Windows.

### platform.portability.042 — Console I/O has no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement terminal encoding, capability, color, prompt, and byte output for the chosen second
platform behind the existing common formatting layer.

### platform.portability.043 — Stack capture has no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Provide address capture and current-image discovery for the chosen second platform behind the
runtime host boundary.

- Related: platform.portability.003, platform.portability.045, platform.portability.044

### platform.portability.044 — Debug-symbol access has no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Locate and read the target's debug information for captured addresses, leaving parsing and
presentation in the existing common layer.

- Related: platform.portability.043

### platform.portability.045 — Debugger integration has no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement debugger detection, break/attach behavior, and any debugger-facing host operations
independently of stack-symbol presentation.

- Related: platform.portability.003, platform.portability.043

### platform.portability.046 — Input devices have no second-platform backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement keyboard and gamepad acquisition for the chosen second platform while keeping normalized
state and policy in common code.

### platform.portability.050 — No second-platform surface and presentation backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Inherited from [platform.portability.032](#platformportability032--process-services-have-no-second-platform-backend), and gated by it.
The filenames already expose most of the seam: `surface.win32.swg`, `application.win32.swg`,
`clipboard.win32.swg`, `dragdrop.win32.swg` and `cursor.win32.swg`. The retained tree, layouts,
themes, controls and the toolkit-owned file dialog are platform-neutral. That is a good boundary,
but five replacement files are not yet a porting plan.

Choose one platform and implement the application loop, surface creation/destruction, native
resize/move/minimize, renderer presentation, and cursor as the first independently testable slice.

- Related: platform.portability.051, platform.portability.057, platform.portability.060

### platform.portability.053 — No second-platform text-input routing

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Translate committed native text input into the portable text event independently of IME
composition.

- Related: platform.portability.049, platform.portability.052, platform.portability.061

### platform.portability.055 — No second-platform clipboard integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement clipboard ownership and platform-format conversion behind the portable typed-value
contract.

- Related: platform.portability.050, platform.portability.024

### platform.portability.057 — No second-platform GUI packaging

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Package the GUI runtime and native dependencies for the chosen second platform.

- Related: platform.portability.050, platform.portability.058, platform.portability.059

### platform.portability.058 — No second-platform GUI font integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Connect GUI font selection and fallback to the installed-font catalog for the chosen platform.

- Related: platform.portability.016, platform.portability.057

### platform.portability.059 — No second-platform file-dialog integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Connect the toolkit-owned file dialog to the target filesystem and native path expectations.

- Related: platform.portability.033, platform.portability.057

### platform.portability.060 — Accessibility has no second-platform integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Map the platform's native assistive-technology service to the accessibility contract from platform.portability.048.

- Related: platform.portability.048, platform.portability.050, platform.portability.061, platform.portability.062

### platform.portability.061 — IME has no second-platform integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Map the platform's composition and candidate-window service to the input-method contract from
platform.portability.049.

- Related: platform.portability.049, platform.portability.050

### platform.portability.062 — Drag and drop has no second-platform integration

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

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

### platform.portability.063 — Spatialization is coupled to an unused X3DAudio handle

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
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

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Submix voices are created with `XAUDIO2_VOICE_USEFILTER` in `src/driver/xaudio2.swg`. The
  capability is requested and no API exposes it.
- XAudio2 gives a per-voice low-pass, high-pass, band-pass and notch filter once that flag is set.
- Next: specify portable filter kinds, cutoff, resonance, update timing, and unsupported-capability
  behavior on `Voice` and `Bus`, then map the first implementation to XAudio2.
- Complete when: no public filter contract names XAudio2, Windows uses its native filters, and a
  second backend can implement or reject the same operation explicitly.
- Related: std.audio.008, std.audio.009, std.audio.014

### platform.portability.065 — Audio has no real non-Windows backend

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- `DriverKind` is `Default`, `NoSound`, `XAudio2`. Off Windows, `Default` resolves to silence.
- The backend boundary in `src/driver/backend.swg` is clean and already has two implementations, so
  a third is additive rather than structural. CoreAudio and ALSA or PulseAudio are the obvious
  targets; WASAPI directly would also remove the XAudio2 dependency on Windows.
- Complete when: one chosen non-Windows target opens a real output device and passes the common
  engine, voice, bus, streaming, and device-lifecycle contract while `NoSound` remains explicit.

### platform.portability.066 — Renderer backend choice has no target matrix

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- `render/` has `cpu` and `ogl`. There is no Vulkan, Direct3D, Metal or WebGPU path.
- On Windows this is the weakest choice available: OpenGL driver quality varies widely, and some
  ARM devices have no usable implementation at all. Skia ships GL, Vulkan, Metal and D3D.
- This also intersects platform.portability.032. Choose the next renderer from the operating systems and hardware the
  project intends to ship, rather than adding a backend independently of the port plan.
- The backend boundary is already two implementations deep, so a third is additive.
- Complete when: the supported OS/GPU matrix names the default and fallback renderer for each
  target, and the next required backend presents through the portable surface contract.

### platform.portability.067 — A collection face is selected by name, and a localized Windows will miss

- Recorded: 2026-08-08 06:23
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

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

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Evidence: a capture leaves as a file, bitmap clipboard data, or an outgoing drag, but cannot be
  copied as a virtual file. The obvious current implementation reuses `DragData` through
  `OleSetClipboard`, which would make OLE the application contract.
- Next: add the virtual-file descriptor and deferred contents to std.gui.001's portable typed clipboard,
  then map them to OLE only in the Windows backend.
- Complete when: paste targets receive the file and bitmap media on Windows, while Swag Capture
  calls no OLE API and another clipboard backend can publish the same virtual file.
- Related: app.capture.001, std.gui.001

### platform.portability.069 — Capture OCR is specified as a Windows-only service

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
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

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Snagit's most-cited feature; ShareX has it too. Capture a window taller or wider than the screen
  by scrolling it and stitching the frames.
- Cost: real. Windows can drive scrolling through UI Automation or synthesized messages, while
  other window systems expose different capabilities. Keep overlap detection and frame stitching
  common, and put window discovery, scroll requests, bounds, and refusal in a native backend.
- Sequence it after the portability inventory, runtime host, process, and filesystem work, and scope it to the common cases — a browser page, a document, a list
  view — rather than promising it works everywhere.
- Complete when: the common stitcher consumes backend-neutral frames and scroll results, the
  Windows backend covers the stated common cases, and unsupported targets fail explicitly.

### platform.portability.071 — Cross-platform capture backend

- Recorded: 2026-08-08 06:23
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

`src/screenshot/screenshot.win32.swg` and the GDI dependency are the whole platform boundary on the
capture side. The editor, the forms, the library, and the serialization are already portable.

- Complete when: one chosen non-Windows backend captures the supported screen/window/region set and
  the application imports no raw OS binding outside named capture backends.

### platform.portability.073 — Swag Scope has no portable thumbnail-provider boundary

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: the image, SVG, and Markdown views can produce a representative bitmap; Explorer asks for
  one and gets nothing.
- Next: define a bounded thumbnail request over the common viewer renderer, then implement the
  Windows Explorer provider without exposing its COM types to viewer code.
- Complete when: registered formats produce bounded thumbnails on Windows and another desktop
  thumbnail service can consume the same renderer contract.
- Related: platform.portability.072

### platform.portability.074 — File-type registration is Windows-only

- Recorded: 2026-08-19 10:05
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: `Env.registerApplication`, `Env.associateFileExtension`, and the shell integration entries
  above are the whole platform boundary; the viewers, streaming, and structure readers are portable.
- Complete when: desktop registration goes through whatever portable contract platform.portability.015 settles on.
- Related: platform.portability.001, platform.portability.015

### platform.portability.075 — Keys live in pageable memory

- Recorded: 2026-08-08 06:23
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
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

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Define the portable security capability and its unsupported behavior, register key regions with
  Windows Error Reporting as the first backend, and verify the configured dump policy. Add target
  adapters only where the OS offers an enforceable equivalent.
- Related: platform.portability.075

### platform.portability.077 — Release signing and elevation policy are Windows-only

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
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

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- The boundary is already where it needs to be: system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, plus the WinFsp layer and the mount-point selector. Everything above them — the
  container format, the logical filesystem, the password widget — is platform-independent already.
  Real work, no design risk.
- Related: platform.portability.079

### platform.portability.079 — No macOS filesystem backend

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Add the macOS mount backend and packaging independently of Linux, choosing the supported FUSE or
  native filesystem mechanism explicitly.
- Related: platform.portability.078

### platform.portability.080 — Bare `.swgs` execution has only a Windows shell contract

- Recorded: 2026-08-30 12:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

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
