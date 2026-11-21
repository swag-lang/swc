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

The approved native leaves are described in [bin/PORTABILITY.md](../bin/PORTABILITY.md). The
repository's source-level native-import audit was retired with the Swag tool scripts, so these
ownership rules currently have no automated enforcement. A small native backend is healthy. The
target is that code above it compiles and is tested without importing a native binding, and that a
new platform implements capabilities rather than copies policy.

The following entries implement the target backends and remove the Windows-bound behavior exposed
by portable modules and products. The earlier entries prepare and enforce the same boundaries.

### platform.portability.004 — Complete Linux allocator fault and lifetime validation

- Evidence: the allocator reaches the host only through `__hostPageReserve`,
  `__hostPageCommit`, `__hostPageDecommit`, `__hostPageRelease`, and
  `__hostPageAllocationBase` (the reservation holding an address, used by the electric-mode
  header lookup), wrapped by `allocatorOsReserve`/`allocatorOsCommit`/`allocatorOsDecommit`
  in `bin/runtime/allocator.pages.swg`. Linux implementations in `os.linux.memory.swg`
  pass JIT reservation, decommit/recommit, allocation-base and inaccessible-page recovery probes.
  Allocator borrow callbacks explicitly use the Swag ABI on Linux. pthread cleanup works
  on a joined runtime thread. Compiler-owned cleanup is drained before JIT code is unmapped;
  tests cover rearming, explicit deletion, live threads and waiting for active destructors.
  The page-reservation registry now reopens its process-specific storage after fork, so a child
  cannot publish private reservation addresses into the parent's registry. A native ELF fork
  probe covers an unreleased child reservation and the surviving parent allocation lookup.
  A native Core peer verifies that an electric block's guard page and its freed payload fault.
  A dynamic-library consumer resolves the DLL allocator's electric header with its own runtime
  code, frees the block across the image boundary and verifies clean allocator teardown.
- Next: define how a child may release allocations inherited from its parent after fork.
- Done when: Linux tests cover reserved-but-inaccessible memory, committed pages,
  decommit/recommit, guard-page protection, release, and thread-storage cleanup without
  reporting counters for work the host did not perform.
- Related: platform.portability.003

### platform.portability.041 — Finish Linux hardware discovery validation

- Evidence: Linux CPU counts use thread affinity, not bandwidth quotas; unavailable affinity
  falls back to one processor. MAC lookup returns the first nonzero six-byte address in native
  order, without promising stable machine identity. Process and thread identity use native IDs.
  Memory, display-adjacent and machine capability families remain incomplete.
- Next: finish the remaining memory, display-adjacent and machine capability families.
- Done when: The chosen second host supplies CPU, memory, display-adjacent, and machine capability queries through the portable API, with documented units and explicit unavailable values verified on that host.

### platform.portability.045 — Finish Linux debugger attachment and output

- Evidence: Linux `Debugger.isAttached` reads the calling thread's TracerPid through procfs;
  an attachment limited to another thread does not count. Unavailable or malformed status returns
  false, and the query is explicitly not signal-handler-safe. `debugBreak` emits the runtime
  breakpoint instruction. The unattached main/worker test and a separate importer pass JIT/native.
  A maintained native test run under ptrace observes the attached initial thread and an untraced
  worker, stops on SIGTRAP and resumes successfully. The separate importer also verifies the
  default fatal SIGTRAP action without a tracer and exits normally after traced continuation.
- Linux diagnostic output now writes exact bytes to stderr, retries interrupted writes, preserves
  errno and prevents its own closed-pipe SIGPIPE from terminating the process. JIT/native tests
  cover UTF-8, embedded zero bytes, bounded views and closed pipes.
- Next: define and implement Linux debugger launch/attach with explicit capability and failure
  behavior, independently of stack-symbol presentation.
- Related: platform.portability.003
- Done when: Debugger presence, break, and attach operations on the chosen second host follow an explicit success/failure contract, with tests for attached and unattached behavior independent of stack-symbol formatting.

### platform.portability.046 — Finish Linux input backends and hardware validation

- Evidence: Linux evdev enumeration and normalized state queries support sticks, triggers,
  D-pad and optional neutral controls. There is no device remapping/dead-zone database or atomic
  multi-ioctl snapshot; hotplug and permissions can change enumeration indices.
  Per-slot `FF_RUMBLE` ownership clamps amplitudes and retires effects on stop, close or errors,
  but driver behavior, disconnection cleanup and physical-device calibration remain unverified.
- Next: validate real or uinput devices for connect/disconnect, permissions, calibration,
  optional controls, rumble replacement/stop/shutdown and focus loss. Keep normalized state and
  policy common.
- Done when: The chosen second host acquires keyboard and gamepad state into the normalized input model, including connect/disconnect and focus loss, with platform tests that keep native device identifiers out of common callers.

### platform.portability.057 — Validate Linux GUI packaging on a clean target

- Evidence: `tools/package-linux.py` stages Capture or Scope ELF files, sibling libraries,
  desktop launchers and shipped icons under an install prefix. Required desktop dependencies
  and behavior on a clean target still need validation.
- Next: audit required EGL/OpenGL, X11 and font dependencies, then exercise installed archives on
  a clean target with open, render and close smoke coverage.
- Related: platform.portability.050, platform.portability.058
- Done when: A packaged GUI application on the chosen second platform launches on a clean target with its renderer, fonts, and native dependencies present, and a packaging smoke exercises open, render, and close.

### platform.portability.058 — Finish Linux mixed-script font validation

- Evidence: Linux family selection uses the shared catalog's typographic/legacy names, file
  paths, collection indices and style metadata. Synthetic faces have independent cached glyph
  workspaces. Installed fallback is cached, while the multilingual HTML golden deliberately
  uses bundled CJK/outline-emoji subsets; it cannot validate installed fallback in real workflows.
- Next: exercise mixed-script text, missing glyphs and installed fallback in complete application
  workflows. Bitmap-only color emoji remains outside the outline reader's supported formats.
  The property editor consumes portable owned family names, and `Font.resolveRune` uses cached
  installed fallback.
- Related: platform.portability.016, platform.portability.057
- Done when: The chosen second-platform GUI selects installed faces and fallback families through the portable font catalog, and renders a mixed-script sample without relying on Windows font descriptors.

### platform.portability.060 — Accessibility has no second-platform integration

- Next: map the platform's native assistive-technology service to the accessibility contract from
  platform.portability.048.
- Related: platform.portability.048, platform.portability.050, platform.portability.061, platform.portability.062
- Done when: The chosen second-platform assistive-technology adapter exposes the common control tree, names, states, focus, and actions, with an integration test that inspects and operates supported controls.

### platform.portability.061 — IME has no second-platform integration

- Next: map the platform's composition and candidate-window service to the input-method contract
  from platform.portability.049.
- Related: platform.portability.049, platform.portability.050
- Done when: The chosen second-platform GUI displays composition and candidates, commits or cancels text correctly, and preserves caret and focus state in an integration test using the common input-method contract.

### platform.portability.076 — Crash-dump exclusion has only a Windows-specific design

- Owner: Swag Vault
- Next: define the portable security capability and its unsupported behavior, register key regions
  with Windows Error Reporting as the first backend, and verify the configured dump policy. Add
  target adapters only where the OS offers an enforceable equivalent.
- Related: platform.portability.075
- Done when: Swag Vault reports whether dump exclusion is enforceable on the host; Windows registers key regions with the configured crash-dump policy and a controlled dump inspection proves protected bytes are absent, while unsupported hosts fail explicitly.

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

- Done when: Each shipped Swag Vault target has documented signing, verification, packaging, and elevation policy; the Windows release verifies a signed publisher in the elevation flow, and macOS/Linux packages meet their declared verification gates.

### platform.portability.079 — No macOS filesystem backend

- Owner: Swag Vault
- Next: add the macOS mount backend and packaging independently of Linux, choosing the supported
  FUSE or native filesystem mechanism explicitly.
- Related: platform.portability.078
- Done when: A packaged macOS Swag Vault mount passes the common filesystem and lifecycle tests, including failed mount, open-handle unmount, and shutdown under active I/O, through a documented supported filesystem mechanism.

### platform.portability.023 — System-icon retrieval and caching are coupled in native GUI code

- Next: split `Application`'s system-icon code into a native operation that obtains one image and
  common Swag that caches it, resizes it, appends it to an atlas, and returns a GUI `Icon`. Do the
  same for each cache consumer without making unrelated shell behavior part of this entry.
- Done when: Native code obtains one requested icon image; common Swag owns resize, atlas insertion, reuse, and eviction for every system-icon consumer, with a test proving repeated requests reuse one cached result.

### platform.portability.026 — Portable surface policy remains in native leaves

- Next: keep `Surface` position clamping, headless fallbacks, state updates, and command posting
  common. A native surface backend should only create/destroy/show/move the host window, translate
  input and window-manager events, manage clipboard/drag/drop/tray integration, and expose an opaque
  renderer handle.
- Related: platform.portability.050
- Done when: Position clamping, headless fallback, state transitions, and command posting run from common Surface code on Windows and the chosen second host; native leaves only operate host windows and integrations, with lifecycle tests on both backends.

### platform.portability.027 — Audio backend selection is repeated compile-time dispatch

- Next: replace the repeated `#os == Windows` dispatch in `driver/backend.swg` with a backend
  interface or operation table. Driver selection, validation, voice/bus lifecycle, streaming-buffer
  rotation, gain conversion, state transitions, and codec work stay common; XAudio2 is one
  implementation.
- Related: platform.portability.065
- Done when: Engine, voice, bus, streaming, gain, and state operations dispatch through one backend interface instead of repeated OS branches, and the NoSound and XAudio2 contract suites retain the same observable behavior.

### platform.portability.032 — Validate Linux process ownership and lifecycle

- Evidence: Linux uses `posix_spawnp` with owned argv/environment values and native file
  actions. Pipe sources stay above descriptor 2; only parent endpoints are nonblocking.
  Search uses the parent PATH. Raw native arguments, pre-exec affinity and tree accounting
  are rejected before launch. Input backpressure drains both outputs and handles only the
  caller's newly generated SIGPIPE, without changing process-wide signal disposition.
  Waits own `waitpid` status, retry EINTR and map signal exits to 128+signal. Current-environment
  snapshots copy caller-synchronized glibc data; procfs failures propagate from executable lookup.
- Lifetime constraint: close transfers a live child to one lazily started reaper without killing
  or waiting. Native state outlives the caller's allocator. Core shutdown joins queued children
  before unloading worker code or deleting the sandbox root; a later destructor waits
  synchronously. Serialize owner operations and prohibit external child reaping. Focused unload
  checks do not prove broader concurrent lifetime behavior.
- Next: run Windows process regressions and broader lifetime stress. Do not mark lifecycle
  conformance from raw tests.
- Related: platform.portability.008, platform.portability.009, platform.portability.011
- Done when: The chosen second host creates, waits for, and terminates processes with pipes, exit status, and declared resource capabilities through the common process API, including timeout and child-lifetime tests.

### platform.portability.033 — Finish Linux filesystem services and ownership validation

- Evidence: Linux stream leaves implement descriptor ownership (including descriptor zero),
  partial/interrupted I/O, 64-bit seeking, truncation, metadata queries and flushing. Mapped
  regions align native views, own close-on-exec duplicate descriptors, and synchronize shared
  writes after the parent handle closes. errno is captured before translation to domain errors.
  Raw Linux tests pass in JIT and native ELF, including sparse files beyond 4 GiB, stat layout
  canaries, EOF, invalid descriptors and mapping lifetime. A separate module imports the real
  bindings and calls read/errno/strerror in both execution modes.
  Linux directory creation/removal, current-directory queries/changes, existence checks and
  absolute path construction now have native leaves. Paths reject embedded zero bytes and
  preserve dot components so a symbolic link followed by '..' keeps filesystem semantics.
  File removal, same-filesystem replacement and modification-time updates also have leaves;
  touch preserves access time, and cross-filesystem moves report EXDEV. Raw filesystem tests pass
  in JIT/native ELF, including symlinks, Linux-only filename characters, errno, replacement
  identity, timestamps and open-descriptor lifetime after unlink.
  statx supplies masked creation/access/write timestamps and explicit Linux attribute mappings.
  Directory enumeration uses metadata relative to its open descriptor and distinguishes EOF
  from readdir errors. Raw statx layout/canary and no-follow enumeration tests pass in JIT/native;
  a separate consumer verifies the exported nested struct layout through a real native call.
  Recursive deletion now inspects the requested root before enumerating it, including trailing
  separator and '/.' spellings. Linux symlink-root cases pass through the public API in JIT/native;
  the Windows junction regression still needs a Windows host.
  File opening now maps all creation modes to openat, creates with 0666 filtered by umask,
  sets close-on-exec atomically unless inheritance is requested, retries interrupted open/stat,
  and closes failed directory handles. Create/Truncate reject read-only access before opening;
  Append is an initial seek, so subsequent explicit seeks retain their effect.
  Sixteen raw tests pass JIT/native, including exclusive creation preserving existing content,
  close-on-exec/inheritable flags and truncation observed through an existing descriptor.
  Nine public file/directory/stream tests and two mapping cases pass in JIT/native. They cover
  opening modes, preservation on failed opens, inheritance flags, append seeks, directory rejection,
  concurrent handles, unlink-while-open, root links and owned mappings. A public FileStream pipe
  test proves that a short first read is completed from a later fragment in JIT/native.
  Two more pipe tests signal a confirmed blocked read and a 128 KiB write with SA_RESTART
  disabled. The public stream retries the read and delivers every written byte in JIT/native.
  A non-root permission case verifies EACCES on new reads, writes, creation and directory
  traversal while an already-open descriptor remains readable. Other interrupted I/O,
  permission races and broader common conformance remain.
- Linux sharing contract: this port adopts documented POSIX sharing. Read/Write/Delete/Zero
  impose no Windows-style exclusion; Inheritable controls exec inheritance. The public FileShare,
  open and openWrite documentation states this explicitly. No advisory lock is presented as a
  mandatory sharing guarantee. This was the default implementation choice, not a user-confirmed
  requirement; a request for stricter behavior would require an explicit capability/API decision.
- Watcher ABI checkpoint: inotify and poll declarations now pass 19 raw tests in JIT/native,
  including split-buffer rename cookies, nonblocking exhaustion, explicit watch removal and
  a cancellation pipe waking poll. A separate consumer executes the exported structures/calls
  in both modes. These raw tests do not establish public cancellation, recursive coverage or
  ownership correctness.
- Watcher backend: Linux owns a nonblocking inotify descriptor and a close-on-exec cancellation
  pipe. Poll uses monotonic deadlines and permanent cancellation wakes an outstanding wait.
  Recursive subscriptions skip directory links, reject inode aliases, update descendant paths
  on paired directory renames, and retain rename cookies across calls for a 50 ms move-out grace.
  Adding a subtree reports Overflow for the unavoidable pre-subscription gap. Queue loss, root
  invalidation, unmount and events overlapping an unresolved moved path report Overflow then
  Cancelled; native failures cancel and propagate. Recreate after terminal overflow before
  rescanning. Recursive traversal races may fail the stream rather than silently omit paths.
  Ten public integration cases pass JIT/native for cancellation, repeated close, timeout continuity,
  filtering, recursive rename paths, subtree gaps, move-out expiry/name reuse, ancestor/root removal
  and link exclusion. Recursive fixture setup now explicitly requests parent creation.
  A separately tagged kernel-queue stress test exceeds the observed inotify queue limit
  with alternating create/delete events, then verifies public Overflow followed by
  permanent Cancelled in JIT/native.
  Broader common coverage now passes 40 ordinary filesystem/path/stream/mapping cases and
  four tagged watcher cases in JIT/native. This includes file mutation, text decoding,
  mapped ownership, SCC and cancellation; Windows-only directory/junction cases remain
  outside this Linux run.
- Additional Linux services: `Directory.isRemote` identifies the mounted filesystem through the
  descriptor mount ID, follows links and resolves the nearest existing ancestor. Fixtures cover
  network filesystem names; actual NFS/SMB mounts remain untested. `Directory.freeSpace` uses
  `fstatvfs` available blocks, rejects non-directories and checks byte-count overflow; real temporary
  storage, procfs and invalid paths pass JIT/native. Three FileStream descriptor cases also pass
  JIT/native with the Release compiler, including borrowed descriptor ownership.
- Next: exercise remaining interrupted operations and permission races; run the remaining
  common filesystem/stream/mapping cases, and compare Windows ownership behavior.
- Done when: The chosen second host passes the common directory, file, stream, metadata, path-state, and mutation contract suite, including partial I/O, links, permissions, and error mapping.

### platform.portability.034 — Finish the Linux thread lifecycle backend

- Evidence: the pthread backend gates startup, publishes the kernel TID before initialization
  returns, retains allocator ownership and remembers nonblocking joins. Resource-pressure and
  broader lifetime behavior still need validation.
  Linux priorities are inherited nice offsets (+2, +1, 0, -1, -2), clamped to [-20, 19]. Raising
  priority can fail for lack of permission; only success updates the public level. Retired thread
  identities must not be reused, and real-time scheduling policy is left unchanged.
- Next: exercise thread-creation failures under resource pressure and additional lifetime stress,
  and decide whether to extend Linux priority support.
- Related: platform.portability.035
- Done when: The chosen second host passes common creation, join, yield, sleep, identity, and priority tests, including failed start and orderly shutdown, without duplicating lifecycle policy in its native leaf.

### platform.portability.037 — Validate the Linux timer backend

- Evidence: the common timer worker owns monotonic deadlines, serialized callbacks, missed-
  period coalescing, cancellation and join-before-free. The native leaves create/join threads;
  concurrent owner shutdown still needs stress coverage.
- Next: validate the Windows leaf and stress shutdown/concurrent-owner behavior.
- Related: platform.portability.029
- Done when: The chosen second host passes the common one-shot, periodic, cancellation, wake, and shutdown timer tests while keeping scheduling policy in common code.

### platform.portability.038 — Finish Linux environment services and validation

- Evidence: Linux provides argv, case-sensitive environment queries, locale precedence and
  special-directory resolution. XDG assignments are data, never shell commands; unsupported
  shared media directories return unavailable paths, and sandbox redirection remains common.
  `openFile`/`openUrl` invoke `xdg-open` without a shell; success describes launcher startup.
  `showInFileExplorer` sends an encoded URI to FileManager1 through `gdbus` with a bounded wait.
  `openFileWith` uses the optional OpenURI portal through libsystemd, passes a real descriptor
  with `ask=true`, requires portal version 3 or newer and bounds each D-Bus exchange to two
  seconds. Core retains the connection until unload so acknowledged dialogs survive the return.
  No default-application fallback replaces the chooser, and sandboxed targets receive no writable
  document-portal grant. Private-bus checks do not establish interactive desktop presentation.
- Next: validate chooser presentation on a real desktop. The
  return value reports request acknowledgement, not eventual user selection or application launch.
- Related: platform.portability.010, platform.portability.015
- Done when: The chosen second host provides argument, environment-variable, locale, special-directory, and generic desktop-action operations through the portable API, with explicit unsupported results and focused contract tests.

### platform.portability.040 — Validate Linux sandbox enforcement and startup

- Evidence: Linux canonicalizes existing prefixes before normalizing missing suffixes and fails
  closed on unresolved paths. Containment preserves host case/link semantics; unlinking a final
  link checks its parent without following that link. Remaining conformance must distinguish
  Windows delete-sharing exclusion from POSIX open-descriptor lifetime.
- Next: run the remaining common sandbox and filesystem conformance cases.
  The guards protect Core's operations; they are not an OS security boundary for arbitrary native
  calls and do not make path checks and subsequent mutations atomic against concurrent renames.
- Related: platform.portability.038, platform.portability.010
- Done when: The chosen second host applies sandbox restrictions before user code and imported native modules run, rejects forbidden filesystem and process actions in integration tests, and reports unsupported enforcement explicitly.

### platform.portability.001 — Complete the Linux repository test gate

- Evidence: `tools/linux-tests.py all` covers compiler suites, workspace fixtures, standard
  modules, examples, applications and reference through shared Windows/Linux command builders.
  Remaining recorded GUI leads include strict Mesa contour differences at confirmation focus,
  floating-sheet edges and property-menu separators, plus platform-dependent fixture paths and
  unavailable application capabilities. Reproduce them on the synchronized checkout before
  changing geometry, coverage or expectations.
  Under Xvfb, Scope cases have intermittently stopped after `event=start`, with the main thread
  waiting and no completion; isolated reruns passed. Panicking cases could leave the same wait.
  A full uninterrupted campaign must distinguish this lifetime failure from a rendering mismatch.
- Next: fix remaining failures at their owning boundaries and complete one uninterrupted
  campaign on the synchronized checkout.
  Keep functional, golden and stress coverage, golden expectations and failure status.
  Select native `integration.*` families separately with their service/hardware prerequisites.
  Prioritize this gate before debug-record expansion or unrelated compiler capabilities.
- Done when: one documented Linux command executes every applicable repository test family,
  produces a complete report with no unexplained failure or unexecuted stage, and rejects
  accidental Windows dependencies in neutral sources.

### platform.portability.008 — Validate the argv-first process API

- Evidence: `StartInfo.arguments` is a borrowed nullable string slice; null/empty supplies no
  arguments after argv[0]. Windows serializes vectors with C-runtime quoting, while callers
  needing another grammar explicitly use Windows-only `nativeArguments`. Linux rejects that
  escape hatch. No shell is inserted implicitly. Exact Windows quoting and migrated consumer
  behavior still need supported-host execution.
- Next: run the Windows quoting path and focused Scope/Pixel/Vault consumers on supported hosts.
- Done when: StartInfo accepts an argument vector as its normal API; Windows quoting and Unix
  direct argv preserve empty, spaced, quoted, and backslash-containing arguments in
  child-process tests, with any raw command-line form explicitly named.

### platform.portability.011 — Process-tree resource accounting has no portable capability contract

- Evidence: `Process.supportsResourceMeasurement` is true on Windows and false on Linux.
  Linux rejects `StartInfo.measureResources` with `ENOTSUP` before launch; unmeasured resources
  remain zero. Linux tree accounting has no implementation.
- Next: preserve the stronger resource contract deliberately. Windows Job Objects account a process
  tree; a Linux implementation needs an explicit process-group/cgroup strategy or must report that
  the capability is unavailable rather than silently measuring only the first child.
- Related: platform.portability.032, platform.portability.009
- Done when: A process-resource query reports whether tree accounting is supported, and tests with a child that spawns another process prove supported totals include descendants or return an explicit unavailable result.

### platform.portability.012 — Filesystems have no cross-host conformance suite

- Next: add filesystem conformance tests on each host for Unicode names, links, permissions, partial
  I/O, and recursive traversal.
- Related: platform.portability.033, platform.portability.013
- Done when: The same filesystem contract suite runs on Windows and the chosen second host for Unicode names, links, permissions, partial I/O, and recursive traversal, with host-specific expected capabilities stated explicitly.

### platform.portability.015 — Desktop actions and application registration share one environment API

- Next: separate generic desktop actions (`openUrl`, reveal a path, enumerate monitors, locale,
  special directories) from platform registration (`registerApplication`, file associations, native
  window creation). Registration belongs in an application-integration module with an explicit
  capability/failure contract, not in the portable core environment namespace.
- Related: platform.portability.038
- Done when: Common environment APIs expose desktop actions without registration or native window types; a separate application-integration API reports support and failures for registration, and current Windows callers migrate with focused tests.

### platform.portability.016 — Replace the native installed-font descriptor

- Evidence: `SystemFontFaceInfo` currently stores `LOGFONTW`, so Pixel's public system-font model is
  a Windows descriptor. `FontFileFace` and `FontCatalog` already provide owned portable
  metadata and file/index loading, including a conventional Linux installed-font source.
- Next: migrate the Windows installed-font source and shared `FontFamily` consumers to
  `FontCatalog`/`FontFileFace`, preserving installed-face selection. Keep native handle creation
  only in an optional Windows adapter, not in the portable descriptor.
- Done when: The public installed-font descriptor contains normalized family, subfamily, style, path, and face index without LOGFONTW or native handles, while Windows enumeration still loads and selects the same installed faces.

### platform.portability.018 — Finish installed-family grouping and cache integration

- Next: replace the Windows grouping callbacks and process cache with the common catalog and
  fallback policy. Linux uses an owned process snapshot and caches successful and unsuccessful
  rune lookups. The catalog groups typographic names and retains legacy-name lookup for light
  and semibold faces; Windows parity still needs validation.
- Related: platform.portability.016
- Done when: One common catalog groups scanned faces by family, selects regular/bold/italic fallbacks, and sorts and caches results identically for equivalent Windows and synthetic second-host font lists.

### platform.portability.009 — Finish shared process orchestration and conformance

- Evidence: common `process.swg` owns validation, lifetime dispatch, paired output draining,
  waits, monotonic timeout budgets and termination policy. Ordinary drains cap each stream at
  64 KiB; final drains snapshot available bytes so descendant-held pipes do not delay waiting
  for the direct child until EOF. Linux services captured output during input backpressure;
  Windows input writes remain blocking and need equivalent duplex behavior.
- Next: finish sharing redirection preparation/rollback policy where native ownership permits,
  address Windows duplex input backpressure, and execute the same process contract cases on both
  hosts. Native leaves should spawn, poll/wait, terminate, and read/write/close native endpoints.
- Related: platform.portability.032, platform.portability.008, platform.portability.011
- Done when: Redirection ownership, concurrent stdout/stderr draining, timeout, and cleanup live in common code; Windows and the chosen second host pass the same process contract tests while native leaves only spawn, wait, terminate, and operate endpoints.

### platform.portability.013 — Paths have no target-independent lexical conformance suite

- Evidence: `core/src/tests/cases/functional/filesystem/path.swg` already tests lexical Windows path behavior
  without touching the filesystem.
- Next: extend that coverage to independent target-policy tables for Windows and Unix: root forms,
  case policy, trailing separators, dot segments, invalid names, and normalization. A host must be
  able to exercise both policies without running another OS.
- Related: platform.portability.012
- Done when: One test run on either host exercises Windows and Unix lexical policy tables for root, case, separators, dot segments, invalid names, and normalization, without filesystem access or host-dependent expectations.

### platform.portability.054 — Native input has no portable mouse, touch, and pen adapter

- Evidence: Core windows now expose mouse movement, five button transitions and both wheel axes
  through `WindowCallbacks.onPointer`. X11 uses signed client coordinates and translates wheel
  press packets once, ignoring their release packets and unsupported button numbers. Three Linux
  integration cases pass in JIT/native: packet routing and queued-owner moves, callback closure
  with stale-event disposal after loop restart, and real Xvfb pointer motion. A separate importing
  module passes in both modes. Windows translates client/screen coordinates and preserves fractional
  wheel deltas; its new native integration tests still require execution on Windows.
  These mouse notifications do not provide keyboard modifier snapshots, capture ownership,
  touch/pen identities, or contact cancellation. Windows `WM_POINTER`, `WM_TOUCH`, and `WM_GESTURE`
  still need translation into contacts.
- Next: implement native adapters for the pointer contract in std.gui.011. Add pointer identity,
  contact lifetime and capture cancellation, suppress duplicate compatibility mouse events, then map
  the same contract on the next platform. Keep gesture recognition and arbitration in the portable
  GUI layer.
- Related: std.gui.011, platform.portability.052
- Done when: Windows and the chosen second platform deliver stable pointer identity and contact lifetimes for mouse, touch, and pen through the common event model; cancellation and capture release are tested, and compatibility mouse messages do not duplicate touch or pen actions.

### platform.portability.051 — Finish Linux monitor and DPI integration

- Evidence: Linux enumerates RandR 1.5 monitors, clips the EWMH work area and falls back to root
  geometry. Coordinates are physical pixels with scale one; dimensions do not imply a scale.
  Query extension presence before any RandR opcode, because an absent-extension request can
  close the XCB connection. Per-monitor scale and topology changes still need integration.
- Next: integrate per-monitor scale and live topology updates with the existing Linux monitor
  enumeration and the surface from platform.portability.050.
- Related: platform.portability.050, platform.portability.084, platform.portability.052, platform.portability.056
- Done when: The chosen second-platform surface enumerates active monitors, uses the correct per-monitor scale during open, move, and resize, and updates placement after topology or scale changes without exposing native monitor handles.

### platform.portability.052 — Finish Linux keyboard and input-method routing

- Evidence: Linux routes physical transitions, modifiers, XKB composition and detectable repeat;
  map/group changes refresh portable layout notifications. Held keys retain release identity
  across remaps, while subsequent presses use the new map. Polling snapshots are separate native
  requests, not an atomic sample. Layout-dependent shortcuts, extra buttons and input-method
  transitions beyond XKB groups remain incomplete.
- Next: validate layout-dependent shortcuts and input-method transitions beyond XKB groups.
- Related: platform.portability.050, platform.portability.085, platform.portability.054
- Done when: The chosen second-platform backend reports physical key, modifier, repeat, and layout changes through portable GUI events, with tests covering key-down/up, repeated keys, and text input independently.

### platform.portability.056 — Complete Linux high-contrast and desktop settings notifications

- Evidence: the Linux XSETTINGS adapter tracks live light/dark and reduced-motion preferences,
  including owner loss and replacement. High-contrast policy and other desktop setting sources
  still need an explicit contract and integration validation.
- Next: define high-contrast policy and translate the remaining desktop settings sources into
  portable live settings events.
- Related: platform.portability.082, platform.portability.050, platform.portability.083
- Done when: Changing light/dark or high-contrast settings while the chosen second-platform GUI runs updates its portable settings event and visible palette without a restart, with platform integration coverage.

### platform.portability.082 — System theme changes are ignored

- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` handles `WM_SETTINGCHANGE` only by calling `refreshSystemMotionPreference`; it does not refresh theme policy.
- Next: handle the platform settings-change notification and update live light/dark policy without
  restarting the application.
- Related: platform.portability.083
- Done when: A Windows light/dark setting change refreshes active surface and widget theme policy without restarting or discarding the current document, with an integration test for the settings notification.

### platform.portability.083 — System high-contrast changes are ignored

- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` handles settings changes for reduced motion, but neither that handler nor `application.swg` refreshes high-contrast policy.
- Next: refresh high-contrast policy on the platform settings notification and ensure it overrides
  visual theme choices as required for accessibility.
- Related: platform.portability.048, platform.portability.082
- Done when: A Windows high-contrast change updates active surfaces and controls immediately, overrides conflicting theme choices, and restores the prior user theme when high contrast is disabled; an integration test covers both transitions.

### platform.portability.084 — Display-topology changes are ignored

- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` has no `WM_DISPLAYCHANGE` route; monitor enumeration is not refreshed from a topology notification.
- Next: refresh monitor enumeration, placement constraints, and dependent application state when a
  monitor is added, removed, or rearranged.
- Related: platform.portability.071, platform.portability.051
- Done when: Adding, removing, or rearranging a monitor refreshes enumeration and placement constraints, leaves visible application windows reachable, and has a reproducible Windows integration check.

### platform.portability.085 — Validate Windows input-language transitions

- Owner: std/gui
- Evidence: `KeyboardLayoutChanged` is distinct from application-string `LanguageChanged`.
  Windows `WM_INPUTLANGCHANGE` forwards it through the surface tree; Linux XKB map/group
  changes notify active surfaces. Native Windows layout-switch behavior and input-method
  transitions beyond keyboard groups still need validation.
- Next: validate the Windows message with a native layout-switch integration test and define
  input-method transitions beyond keyboard groups.
- Related: platform.portability.049
- Done when: A Windows input-language change updates layout-dependent keyboard state before the next key event, keeps key identity distinct from produced text, and is covered by a layout-switch integration test.

### platform.portability.086 — No printer discovery or native print-job backend

- Owner: std/gui
- Evidence: `bin/std/modules/gui/src` has no printer enumeration or print-job backend; the portable pagination contract remains std.gui.030.
- Next: enumerate printers and capabilities, open a native job, spool every page from std.gui.030,
  and report failure at each stage. Keep one optional virtual-PDF integration test; correctness must
  not depend on an installed driver.
- Related: std.gui.030, std.gui.033, std.gui.032
- Done when: Printer discovery and capability reporting drive a native job that spools all pages from the portable pagination model; tests cover unavailable printers, start/page/end failures, and cancellation without requiring a permanently installed driver.

### platform.portability.089 — Allocator stress is not run under Windows heap instrumentation

- Next: run the allocator stress suite under Windows Application Verifier and page heap, and make
  the invocation reproducible without folding it into failure injection.
- Related: runtime.allocator.001
- Done when: A documented repeatable command runs the allocator stress suite under Windows Application Verifier and page heap, checks the tool's reported failures and test exit status, and leaves operating-system failure injection to the native allocator tests.

### platform.portability.021 — Application-message payloads have no ownership contract

- Evidence: application-message identifiers are platform-neutral, but `SysUserEvent.param` carries
  one opaque `u64` by value. It supplies no ownership or lifetime contract for any data the caller
  encodes through that integer.
- Next: give messages an owned payload and document its dispatch lifetime independently of tray
  interaction.
- Related: platform.portability.022
- Done when: A sender can release or mutate its source buffer after posting a message without changing the payload observed during dispatch, and tests cover queued delivery, cancellation or target destruction, and payload cleanup without exposing native handles in the common event API.

### platform.portability.035 — Named Linux events and synchronization stress remain

- Next: implement named interprocess events behind `Sync.Event.initNamed`, then extend runtime
  lock, read-write lock, condition and event stress across shutdown and module boundaries.
- Evidence: Linux runtime locks and conditions use the `__hostLock*` and `__hostCondition*`
  hooks. Core now implements unnamed auto-reset and manual-reset events with pthread mutexes
  and conditions. Signals assigned to existing waiters survive a subsequent reset; signals
  with no waiter coalesce. Ownership requires all operations to finish before release.
  Five public cases pass in JIT/native: deferred error handling without allocation/hooks,
  pre-wait coalescing, publication between threads, broadcast and reset during active waits.
  A separate archive consumer completes 100 request/completion exchanges in both modes.
  Native storage sizes and alignments agree with the host glibc C headers. The pthread bindings
  declare that they do not dispatch callbacks, and event status paths avoid panic hooks, preserving
  the temporary-borrow retirement contract used by Pixel's synchronous render requests.
  Pixel's six ordinary renderer/thread tests pass natively, including failed wait/signal retirement.
  Windows still needs native validation; cross-target Core sema on Linux stops at the existing
  Windows runtime log/logf imports, before it can validate the complete module.
- Named scope remains Windows-only: interprocess events must retain shared-name scope,
  reset mode, signal-before-wait behavior and independent opener lifetimes without exposing
  Windows handles or the `Local\` namespace to common callers.
- Related: platform.portability.034, language.parallelism.003
- Done when: Linux passes synchronization stress and shutdown tests, and named Core events
  preserve cross-process scope, reset and lifetime semantics through the portable contract.

### platform.portability.062 — Drag and drop has no second-platform integration

- Next: map the platform's data-transfer and gesture service to the drag and drop contract the Win32
  backend already implements.
- Related: platform.portability.050
- Done when: The chosen second-platform GUI backend can accept and initiate the data and gestures supported by the Win32 drag-and-drop contract, with explicit cancellation and data lifetime behavior, while common GUI callers and tests use no native transfer type.

### platform.portability.022 — Application-to-application messaging has no portable contract

- Evidence: Swag Scope is a concrete consumer: an association launch currently creates another
  process.
- Next: give single-instance/application messaging a portable contract. The Windows backend may keep
  `FindWindow`/`SendMessage`; another backend may use a local socket or bus. The public identifier,
  payload, delivery, timeout, and failure semantics must be the same. Forward Swag Scope's requested
  file to a running instance through this contract, preserving launch failure reporting and the
  receiving application's ownership of queued document opens.
- Related: app.scope.001
- Done when: A second Swag Scope launch forwards its requested file to the running instance on Windows and the chosen second platform, or reports a bounded delivery failure; tests cover payload ownership, timeout, receiver shutdown, and exactly one queued open.

### platform.portability.090 — A COM object's ABI header is held first by a comment, not by the language

- Evidence: the four OLE objects in `bin/std/modules/gui/src/dragdrop.win32.swg` copy their
  interface header as a first `lpVtbl` field commented "must stay first", and
  `dropTargetOf`, `dataObjectOf`, `formatEnumOf`, and `dropSourceOf` recover the Swag object
  with `cast(*T, cast(*void, itf))`. Nothing checks the invariant, so a field inserted above
  `lpVtbl` silently breaks every OLE callback.
- Blocker: composing with `using base: IDropTarget` (and siblings) makes recovery a checked
  descent. However, `lpVtbl` is non-nullable in the `ole32.swg` interface structs, so the
  composed objects have no valid zero default, and `Memory.new'DragFormatEnum()` and
  `Memory.new'Surface()` stop compiling.
- Next: decide how a composed ABI header reaches its vtable pointer under zero-initialization:
  a nullable `lpVtbl` in the four `ole32.swg` interface structs, a `late` field, or an
  explicit constructor at each creation site. Then compose the four objects and delete their
  `cast(*void)`.
- Done when: the four OLE objects compose their interface, the recovery is a checked descent,
  and no comment in the file asks a field to stay first.
- Related: compiler.safety.033

### platform.portability.078 — Complete Linux FUSE and session integration

- Owner: Swag Vault
- The existing boundary includes system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, the WinFsp layer and mount-point selector, and `autounmount.win32.swg` for session
  lock, suspend, and idle monitoring. The container format, logical filesystem, password widget,
  and auto-unmount decisions live above those native mechanisms. The Linux mount backend remains
  this entry's outcome; native session and idle monitoring must also be accounted for before the
  full application port ships.
- Evidence: the FUSE3 backend mounts real volumes and passes read/write, rename, open-unlink,
  retained-descriptor I/O, unmount and read-only remount checks. Per-volume advisory locks prevent
  conflicting processes from opening writable containers. Three callback/rename cases pass JIT/native
  with the Release compiler, including no-replace and file/directory mismatch failures.
  Private D-Bus peers exercise the real libsystemd monitor for LockedHint, queued lock/unlock,
  idle hints and sleep-inhibitor release/reacquisition. A separate Xvfb integration case passes
  JIT/native through the real XScreenSaver idle query. These checks do not validate an actual
  desktop login manager or physical suspend.
- Next: complete physical-session and active-request shutdown validation, then validate the
  mounted workflow through the GUI and packaged application.
- Done when: a Linux mount passes the common filesystem behavior and lifetime tests,
  including failed mounting and shutdown while requests are active.
- Related: platform.portability.079

### platform.portability.050 — Finish Linux surface, presentation and device-loss validation

- Evidence: the Linux XCB/X11 and EGL adapters provide windows, presentation, input, clipboard
  and drag/drop mechanisms. Headless Core consumers retain optional desktop/GL dependencies.
  Complete application workflows, physical GPUs, connection-loss and module-unload stress remain
  unverified. Native Wayland, IME composition and accessibility are separate capabilities.
  EGL contexts lack lose-on-reset robustness, so `RenderOgl.recoverLostDevice` cannot recover a
  Linux GPU reset; windows can remain on a context that draws nothing.
- Constraints: keep window operations on the creating thread and invalidate owners before native
  state is released. A renderer's shared context must outlive individual window surfaces; resize
  can require surface recreation while preserving that context. Retain optional RandR/XFixes
  libraries until disconnect and check extension presence before negotiation. Native X11 swap
  publication is asynchronous, so pixel verification must wait for presentation.
  `WindowOptions.stopLoopOnClose` and `WindowCallbacks.onCloseRequest` give consumers explicit
  lifetime policy. GUI defers close until renderer borrows retire; no implicit last-window
  shutdown may replace that policy. The retained tree, layout, themes and toolkit file dialog
  stay platform-neutral. `surface.win32.swg`, `application.win32.swg`, `clipboard.win32.swg`,
  `dragdrop.win32.swg`, `cursor.win32.swg` and `nativetext.win32.swg` identify native mechanisms,
  not a porting plan.
- Next: validate complete application workflows and physical desktop/GPU behavior, finish dynamic
  connection-loss/module-unload stress. Create the shared EGL context with
  `EGL_EXT_create_context_robustness` and implement its `replaceLostContext`, then run the
  `integration.renderer.reset` tests on a physical GPU. Native Wayland, IME composition and
  accessibility remain distinct capabilities. The X11 GUI uses explicit
  compositor-backed presentation; retain pixel-level tests when changing visual/alpha selection.
- Done when: a non-trivial GUI sample opens, lays out, paints, resizes, and closes on the
  second platform. Platform-neutral events expose no native message numbers, and Windows and
  headless contract tests remain green. Focus, DPI, clipboard and input integrations retain
  their own entries and tests.
- Boundary: a GUI port does not complete the applications. Swag Capture still requires
  platform.portability.071; Swag Vault requires platform.portability.078 or .079. Both also
  need the runtime, filesystem and font services used by their common code.
- Related: platform.portability.003, platform.portability.033, platform.portability.034,
  platform.portability.035, platform.portability.051, platform.portability.057,
  platform.portability.058, platform.portability.060

### platform.portability.080 — Finish shell and desktop `.swgs` execution contracts

- Evidence: `tools/setup.bat` registers the current user's compiler path and `SWAG_PATH`, but
  does not claim a file association. `tools/setup.sh` maintains a marked Bash/Zsh profile block
  and reports bare `.swgs` execution as unsupported, with an explicit compiler command.
  Fresh Windows shells and desktop-launch behavior still need a verified contract.
- Next: validate Windows bare-script behavior in fresh shells and define desktop-launch behavior
  per host. Machine-wide mutation remains explicit and opt-in.
- Done when: setup reports whether bare execution is supported for the current shell and either
  configures it safely or prints the exact remaining elevated step; a fresh `cmd.exe` and
  Windows PowerShell 5.1 session execute a representative bare `.swgs` script according to that
  contract; a supported non-Windows shell either executes the same representative script
  through its documented launcher/shebang path or reports bare execution as unsupported with an
  exact command; existing double-click behavior remains intact; and moving the checkout and
  rerunning setup refreshes stale interpreter paths, and removal instructions undo installed
  associations.
- Related: compiler.build.016

### platform.portability.066 — Renderer backend choice has no target matrix

- `render/` has `cpu` and `ogl`. There is no Vulkan, Direct3D, Metal or WebGPU path.
- Linux x86-64 now has an EGL/XCB context and buffer-swap adapter for the existing OpenGL backend.
  The tested configuration is Xvfb plus Mesa software rendering, requiring EGL_EXT_platform_xcb
  and OpenGL 3.3 compatibility. Pixel's native and JIT integrations now exercise worker presentation,
  asynchronous readback and renderer resources shared across independent window surfaces. GUI
  presentation, physical GPU-driver coverage, native Wayland and a production fallback policy remain open.
- No measured OS/GPU capability matrix currently establishes which backend can present on each
  intended target; the CPU renderer is an existing fallback, not a substitute for that matrix.
- This also intersects platform.portability.050. Choose the next renderer from the operating systems and hardware the
  project intends to ship, rather than adding a backend independently of the port plan.
- The backend boundary is already two implementations deep, so a third is additive.
- Next: record which renderer presents on each intended OS/GPU target and choose the next
  backend from that matrix and the platform.portability.050 port plan.
- Done when: the supported OS/GPU matrix names the default and fallback renderer for each
  target, and the next required backend presents through the portable surface contract.

### platform.portability.067 — Collection-face selection depends on one localized family name

- Evidence: `TypeFace.createFromHfont` reads the `ttcf` collection through GDI, and
  `loadFaceForFamily` (`pixel/src/text/typeface.win32.swg`) picks the face whose
  `Face.familyNameAt` equals the LOGFONT family. Windows localizes that family, while
  `familyNameAt` returns the best-scoring, English-biased `name` record. On a mismatch face
  zero is taken silently, which selects the wrong family rather than refusing. For example, a
  Japanese or Chinese Windows enumerates `ＭＳ ゴシック` or `宋体`.
- Next: either let `truetype` answer whether a face declares a given family in any `name`
  record and match on that, or read the face index from the offset tables. The offset-table
  route is locale-proof but needs both the synthesized single-face file and the collection,
  so it reads the font twice.
- Done when: the Windows adapter returns the portable file-and-face-index descriptor from
  platform.portability.016/platform.portability.019 without locale-dependent matching, and the
  same descriptor accepts the conventional Linux `FontCatalog.loadSystem` source.
- Related: platform.portability.016, platform.portability.019

### platform.portability.019 — Windows installed-family selection still requires GDI

- Evidence: `TypeFace.createAt(fullName, bytes, faceIndex)` and
  `TypeFace.loadAt(fullName, faceIndex)` now select a zero-based collection face. Existing
  `create`/`load` select index zero. Cache keys include both name and index; native and JIT
  regressions cover distinct styles, repeated lookups, invalid indices, and copied-byte lifetime.
  Installed-family selection still uses `createFromHfont`; it does not yet supply a portable
  descriptor to these APIs.
- Next: migrate Windows installed-family selection to the file/index path already used by
  `FontFileFace.load` and Linux fallback, keeping `createFromHfont` as an optional adapter.
- Done when: a system-family selection loads the requested collection face from its
  descriptor without manufacturing a GDI font handle.
- Related: platform.portability.067, platform.portability.016

### platform.portability.025 — Drag-preview premultiplication still lives in the Windows adapter

- Evidence: clipboard and OLE DIB payloads now use `Pixel.Bmp.EncodeOptions{fileHeader: false}`;
  the shared encoder owns row alignment, channel ordering, and straight-alpha conversion.
  `buildDragBitmap` still walks pixels, premultiplies channels, and writes a top-down native
  bitmap for the shell drag preview.
- Next: use the existing Pixel pixel-format and alpha-conversion operations for that preview,
  keeping only native bitmap creation, row transfer, and handle ownership in the Windows leaf.
- Done when: the preview path has no private color-conversion loop and native tests protect
  orientation, transparency, and bitmap lifetime across success and failed attachment.
- Related: platform.portability.014, platform.portability.062

### platform.portability.029 — Validate common periodic scheduling and cancellation

- Evidence: `time/timer.worker.swg` owns a worker per timer, monotonic deadlines, serialized
  periodic callbacks, skipped missed periods, cancellation and join-before-free. Native leaves
  only create/join threads. Distinct timers can overlap; a single timer cannot overlap its own
  callbacks. Windows parity and the cost of many dedicated timer threads remain unverified.
- Next: run the same cases on Windows and assess the dedicated-thread cost for many timers.
- Done when: the same timer lifecycle and periodic/cancellation tests run over Windows and
  the chosen second backend without duplicating scheduling policy.

### platform.portability.003 — Finish the runtime host ABI boundary

- Evidence: `bin/runtime/os.win32.swg` already provides named `__hostTls*`, thread-storage,
  `__hostThread*`, lock/condition, page-allocation, and image/debug-section hooks. The remaining
  boundary is not a missing host API from scratch: the leaf still combines those mechanisms with
  command-line conversion, test exception recovery, and debug-section decoding policy.
- Next: specify the existing host operations and their ownership/failure contracts, then move
  target-independent policy out of the Windows leaf. Keep native context capture, image lookup,
  byte output, library loading, and process termination as explicit host mechanisms.
- Done when: another host can implement the same documented operations without copying
  command-line or debug-data parsing policy, and Windows runtime tests retain their behavior.
- Related: platform.portability.004

### platform.portability.010 — Early argument lookup retains a Windows command-line fallback

- Evidence: Core's premain command-line string fallback is confined to environment.win32.swg.
  Name/value matching now lives in `findRunArgumentIn`, shared by both backends. Linux uses argv
  directly because ELF startup publishes it before module initialization. Windows still searches
  `Swag.args()` first, then parses `GetCommandLineA` when native early startup needs the fallback.
- Linux startup now passes a native peer that sees the sandbox armed before #init/#premain and
  a separate importing executable that sees it armed before its own hooks.
- Next: make Windows argv available before native module initialization and remove that
  platform's early command-line fallback.
- Done when: native and compile-time early argument lookup use the same populated vector
  and preserve sandbox, smoke, and corpus argument behavior.
- Related: platform.portability.008

### platform.portability.014 — The Windows virtual-key alias remains in portable input declarations


- Evidence: image handle conversions and `Surface.win32Handle` already live in Windows
  adapter files. Their native signatures are intentional optional interoperability.
  `Input.VirtualKey`, however, is still declared in neutral `key.swg` and exercised in
  neutral `key.swg`; the conversion functions themselves live in `keyboard.win32.swg`.
- Next: keep that alias and its tests with the optional keyboard adapter. Common declarations
  and consumers should need only `Input.Key` and normalized events.
- Done when: a neutral input compilation contains no virtual-key declaration or native
  adapter dependency, while Windows keyboard conversion tests still cover the mapping.

### platform.portability.065 — Complete Linux audio consumer and hardware validation

- Evidence: Linux Default selects the dynamically loaded FAudio backend; NoSound remains explicit.
  Real PCM disk-output tests cover source/submix/mastering voices, gain, pitch, routes, seek,
  looping and repeated stop. Missing libraries/devices and portable teardown regressions pass.
- Swag Scope now compiles with all eleven dependencies, loads a real WAV and renders its
  waveform under Xvfb/Openbox. The sandboxed graphical smoke passes; its intentional NoSound
  policy does not validate playback. A separate bounded native run outside that sandbox, with
  private XDG directories and the real FAudio SDL disk driver, produces 3,002,880 bytes of PCM
  after an XTEST playback shortcut, with measured peak amplitude 0.97866.
- Next: validate a physical output device and device loss/recovery. Keep PCM software-device
  evidence distinct from physical hardware coverage.
- Done when: the application consumer and device lifecycle preserve the common voice, bus and
  streaming contracts on Linux, including unavailable-device behavior.
- Related: platform.portability.027

### platform.portability.048 — Accessibility has no portable semantic tree or Windows adapter

- Evidence: the GUI module has no `WM_GETOBJECT` handler, UI Automation provider, MSAA adapter,
  or common accessibility tree. Its custom controls therefore expose no semantic roles, names,
  states, or actions to assistive technology. Existing keyboard navigation supplies no such model.
- Next: define a platform-neutral accessible tree with roles, names, values, states, focus, and
  actions, validate it through the headless host, then expose it through a Windows UI Automation
  provider rooted at the surface. No portable widget or event may mention UIA or a native message.
- Done when: Narrator, NVDA, and JAWS can inspect and operate the first supported controls on
  Windows, the semantic tree is backend-independent, and platform.portability.060 can map another OS without changing
  widget APIs.

### platform.portability.049 — Text composition has no portable contract or Windows IME adapter

- Problem: no `WM_IME_STARTCOMPOSITION`, `WM_IME_COMPOSITION`, `WM_IME_ENDCOMPOSITION`,
  `WM_IME_SETCONTEXT` or `WM_IME_NOTIFY`. Text input is `WM_CHAR` and `WM_KEYDOWN` only.
- Missing behavior: editors have no representation of an active composition, its clauses, or the
  candidate-window location. Receiving committed characters through ordinary text events does
  not prove that composition and candidate selection work correctly.
- Next: define backend-neutral composition start/update/commit/cancel events, clause styling, and
  candidate-window geometry, then translate the Windows IME messages into that model. The caret
  geometry needed for placement already exists in `EditBox`.
- Done when: Chinese, Japanese, Korean, and Vietnamese composition works on Windows, headless
  tests cover the common model, and platform.portability.061 can add another OS without changing editor APIs.

### platform.portability.088 — Network transports need portable host backends

- Owner: the `net` module from std.net.001.
- Evidence: Windows and Linux leaves implement blocking IPv4/IPv6 TCP, UDP, and DNS behind
  portable address and socket owners. Linux uses close-on-exec sockets, suppresses SIGPIPE per send,
  retries interrupted transfers/accept, and completes interrupted connects through poll and SO_ERROR.
  Linux focused tests cover loopback, EOF, UDP delivery, IPv6, resolver behavior, and HTTP streaming.
  Windows bindings and implementations exist, but equivalent runtime coverage has not been run.
  Linux HTTPS still uses a lazily loaded libcurl backend with system trust, bounded bodies and
  headers, explicit redirects, and whole-transfer deadlines. HTTP servers now parse bounded
  requests and stream responses. TLS streams, readiness, and cancellation remain separate contracts.
- Next: run equivalent Windows integration coverage for IPv6, UDP, resolver failures, and socket
  lifetime; keep native handles and error translation inside host leaves, and add readiness only
  after the common concurrency contract is decided.
- Done when: both host backends pass equivalent loopback, partial-transfer, resolution-failure,
  and handle-lifetime tests without exposing native types to callers.
- Related: std.net.001, std.net.002, std.net.003, std.net.004, language.parallelism.001.

### platform.portability.081 — Foreign vector ABIs are unavailable

- Intent: support explicitly selected platform vector ABIs for foreign declarations where the ABI
  is stable, while continuing to reject an ambiguous bare C-vector contract.
- Next: choose the first explicit foreign vector-ABI annotation and the C/C++ fixtures for
  Windows x64 that pin its parameter and return passing.
- Done when: supported Windows x64 and one non-Windows target's vector parameters and returns
  interoperate with C/C++ fixtures, unsupported conventions fail semantically, and the contract is
  documented per target.
- Related: compiler.codegen.019.

### platform.portability.072 — Swag Scope has no portable preview-provider boundary

- Intent: the shipped viewers are reachable from where a file is selected. This is the whole reason
  Quick Look won its category: select, look, move on, without launching an application.
- Evidence: Apple exposes Quick Look from Finder with Space and adjacent-item navigation. Windows
  preview handlers likewise render a selected file without launching its associated application,
  but add a security constraint Swag Scope must preserve: the handler runs out of process, at low
  integrity by default, and should receive a host-owned stream rather than ambient path authority.
- Next: define an out-of-process-safe preview request/result contract, then host it in an Explorer
  preview handler as the first OS adapter.
- Done when: Explorer renders the same supported views through `--register-file-types`, the
  application window is not required, a selected file reaches first presentable content within the
  shared preview budget, decoder failure cannot damage Explorer, and another desktop preview service
  can host the contract.
- Note: the handler hosts a view in a process it does not own, so the viewer request/result contract
  has to be usable without the application window. That constraint is worth checking before committing.
- Related: app.scope.viewers.009, app.scope.viewers.011, platform.portability.073,
  platform.portability.074

### platform.portability.031 — Decide deliberately whether Swag should ship its own libm

- Evidence: the transcendental intrinsics (`Swag.sin` … `Swag.pow`) call UCRT at runtime, and
  compile-time folding uses the compiler host's C++ math library. A hosted Linux target can
  call the platform libm instead. A handwritten library is not a prerequisite for Linux:
  these operations have no scalar x64 instruction, and a production implementation must
  handle huge-argument reduction, subnormals, infinities, NaNs, signed zero, every `pow`
  corner, bounded error, and competitive speed.
- Next: decide whether any product goal requires an owned libm: freestanding builds,
  bit-reproducible math across hosts, independence from platform libm quality, or a specified
  accuracy/performance tradeoff. If one does, port a proven, permissively licensed corpus. State
  the `f32`/`f64` error and special-value contract, test `f32` exhaustively and `f64` with
  differential and adversarial vectors, benchmark against each system libm, and make constant
  folding use the same semantics. Keep hardware lowerings for `sqrt`, rounding, abs, min/max,
  FMA, bit operations, and atomics.
- Done when: the hosted Linux ABI can ship without an owned libm, and any owned-libm goal has
  recorded reasons, semantics, provenance, and acceptance tests.
- Related: platform.portability.001

### platform.portability.063 — Spatialization is coupled to an unused X3DAudio handle

- `src/driver/xaudio2.swg` calls `X3DAudioInitialize` and stores the handle in `x3DInstance`. That
  handle is never read again. The 3D engine is initialized on every engine creation and does
  nothing.
- Next: define portable listener, source-position, distance-attenuation, and channel-matrix
  semantics, then lower them through X3DAudio in the Windows backend. Other backends may use their
  native spatializer or an explicitly supported common fallback.
- Done when: the public model contains no X3DAudio types, the Windows matrix is validated, and
  a backend can declare or implement the same capability without changing `Voice`.

### platform.portability.064 — Voice filters are specified only by XAudio2 capabilities

- Submix voices are created with `XAUDIO2_VOICE_USEFILTER` in `src/driver/xaudio2.swg`. The
  capability is requested and no API exposes it.
- XAudio2 gives a per-voice low-pass, high-pass, band-pass and notch filter once that flag is set.
- Next: specify portable filter kinds, cutoff, resonance, update timing, and unsupported-capability
  behavior on `Voice` and `Bus`, then map the first implementation to XAudio2.
- Done when: no public filter contract names XAudio2, Windows uses its native filters, and a
  second backend can implement or reject the same operation explicitly.
- Related: std.audio.008, std.audio.009, std.audio.014

### platform.portability.068 — Capture clipboard files are specified as OLE data

- Evidence: a capture leaves as a file, bitmap clipboard data, or an outgoing drag, but cannot be
  copied as a virtual file. The obvious current implementation reuses `DragData` through
  `OleSetClipboard`, which would make OLE the application contract.
- Next: add the virtual-file descriptor and deferred contents to std.gui.001's portable typed clipboard,
  then map them to OLE only in the Windows backend.
- Done when: paste targets receive the file and bitmap media on Windows, while Swag Capture
  calls no OLE API and another clipboard backend can publish the same virtual file.
- Related: app.capture.001, std.gui.001

### platform.portability.069 — Capture OCR is specified as a Windows-only service

- Problem: no text recognition anywhere in the module. The Windows Snipping Tool has it, Snagit
  has it, ShareX has it. It has gone from a differentiator to an expectation.
- Next: define an OCR provider contract over a pixel selection, bind the Windows OS engine as the
  first provider, and keep provider availability explicit so another OS can use its native service
  or an optional local engine without changing the command.
- Done when: the command returns text through the provider on Windows, absence is reported
  honestly, and capture/editor code imports no Windows OCR type.
- Why this high: it is the most visible remaining reason to reach for the built-in tool instead of
  this one, and the platform does the hard part.

### platform.portability.070 — Scrolling capture has no portable scroll-driving backend

- Snagit's most-cited feature; ShareX has it too. Capture a window taller or wider than the screen
  by scrolling it and stitching the frames.
- Cost: real. Windows can drive scrolling through UI Automation or synthesized messages, while
  other window systems expose different capabilities. Keep overlap detection and frame stitching
  common, and put window discovery, scroll requests, bounds, and refusal in a native backend.
- Next: after the portability inventory, runtime host, process, and filesystem work, define
  backend-neutral scroll requests and frame results for a common stitcher, then cover a browser
  page, a document, and a list view in the Windows backend.
- Done when: the common stitcher consumes backend-neutral frames and scroll results, the
  Windows backend covers the stated common cases, and unsupported targets fail explicitly.

### platform.portability.071 — Cross-platform capture backend

- Evidence: Linux has X11 screen, region, cursor and window capture with editor publication.
  Isolated X11 checks do not establish decorated-window focus, a physical compositor session
  or native Wayland behavior. X11 pointer capture must start after the selection overlay is shown.
  Keep OS bindings inside the named capture backends.
- Next: exercise the complete capture application with a compositor and window manager, including
  actual window-manager focus changes and decorated windows. Account for native Wayland capture
  through the desktop portal rather than reading the XWayland root alone.
- Done when: one chosen non-Windows backend captures the supported screen/window/region set and
  the application imports no raw OS binding outside named capture backends.

### platform.portability.073 — Swag Scope has no portable thumbnail-provider boundary

- Intent: the image, SVG, and Markdown views can produce a representative bitmap; Explorer asks for
  one and gets nothing.
- Next: define a bounded thumbnail request over the common viewer renderer, then implement the
  Windows Explorer provider without exposing its COM types to viewer code.
- Done when: registered formats produce bounded thumbnails on Windows and another desktop
  thumbnail service can consume the same renderer contract.
- Related: platform.portability.072

### platform.portability.074 — Validate desktop registration from packaged Linux applications

- Evidence: Linux Env registration creates per-user XDG desktop entries and offers or claims
  MIME associations through optional GIO. Isolated native tests cover preserved defaults,
  custom MIME definitions, exact executable/filename quoting, unavailable GIO, failed writes
  and sandbox refusal.
- Next: exercise Capture and Scope registration entry points with installed resource and
  executable locations, and package their desktop entries and icons. The API separation in
  platform.portability.015 remains a distinct design task for both hosts.
- Done when: packaged Linux applications register repeatably, launch the intended executable
  with the selected file, and leave unrelated defaults and desktop entries intact.
- Related: platform.portability.001, platform.portability.015

### platform.portability.075 — Keys live in pageable memory

- Owner: `bin/std` for the locked allocation, Swag Vault for the policy
- Problem: `Crypto.Keys` and the unwrapped master key are ordinary memory. The page file or a crash
  minidump can capture the master key. VeraCrypt locks its key pages.
- Next: define a locked-memory allocation with explicit availability/failure semantics, implement
  it with each target's page-locking primitive, and require Swag Vault's unwrapped keys to use it.
  Keep dump exclusion and lifecycle wiping independently testable.
- Done when: supported targets prove the key pages are locked or refuse securely, and Vault
  contains no direct `VirtualLock`, `mlock`, or equivalent call.
- Related: platform.portability.076

### platform.portability.091 — Finish Linux cache cleanup and fault-boundary validation

- Evidence: cross-target JIT execution uses host context, TLS and process storage; native output
  keeps its target instructions.
  DWARF frame registration preserves C++ cleanup through generated faults, and native ELF/JIT
  tests recover protected-page faults and stack exhaustion. Compiler-owned pthread callbacks
  now retire before their code is unmapped, including active callbacks which delete their key.
  Linux directory locks remain advisory: the cleaner in `Command.Clean.cpp` removes whole trees
  without coordinating with API readers or publication locks in descendant directories.
- Next: coordinate cleanup of entries and their ancestors with API readers/publication, including
  a cleaner racing a waiting reader across directory replacement. Extend fault-boundary coverage
  across native callbacks and nested JIT calls while preserving C++ cleanup.
- Done when: concurrent cleanup cannot invalidate an active reader/publication generation,
  and nested JIT/native fault recovery preserves ownership without stale code or storage.
- Related: platform.portability.001, platform.portability.093

### platform.portability.093 — Finish Linux native debug support

- Missing: register locations, precise lexical lifetimes, inline records, global/constant DIEs
  and enum names in native DWARF. Optimized variables without recorded stack homes are absent;
  unsupported composite types retain opaque names/sizes. GDB expression probes require C because
  Swag has no DWARF language identifier.
- Next: extend debug type/location coverage, with executable and shared-library fixtures that inspect
  emitted records and stop in GDB to verify values and scope boundaries.
- Done when: richer Linux debug records describe the surviving values and scopes without
  inventing locations for optimized-away storage.

### platform.portability.095 — Extend foreign ELF archive ABI coverage

- Evidence: the integrated ELF image writer rejects foreign static TLS sections, direct
  TLS-variable imports and local IFUNC resolvers. Swag-generated objects use pthread-based
  TLS and ordinary functions, so these input forms require separate foreign-ABI support.
- Next: add reduced C/archive fixtures for TLS models and local IFUNC resolvers; implement
  PT_TLS and the corresponding TLS relocations, then IRELATIVE/GOT/PLT resolver handling.
- Done when: foreign TLS storage is isolated across native threads, local IFUNC calls and
  pointers agree in executables and shared objects, and these tests pass without external
  link tools. Imported DSOs may continue to handle their own TLS and IFUNC implementations.

### platform.portability.097 — No GPU screen acquisition

- Evidence: Swag Capture grabs the screen with `BitBlt` and `CAPTUREBLT` into a DIB
  (`screenframesource.win32.swg`), whose cost grows with the area and which paints the cursor into the
  pixels; there are no Direct3D 11 or DXGI bindings under `bin/`. `DwmGetWindowAttribute` and
  `SetWindowDisplayAffinity` are not bound either.
- Next: implement the `std/screen` source contract in std.screen.001, then bind Direct3D 11 and
  DXGI and expose Desktop Duplication: GPU frames with changed and
  moved rectangles, performance-counter timestamps, pointer shape and position apart, crop, scale
  and NV12 conversion on the GPU, and capture across several monitors. Move the still-picture
  `BitBlt` and X11 paths behind the same source. Bind the window bounds and display affinity
  calls used for window targets and for excluding overlays. Report lost access (secure desktop,
  display mode or monitor change, GPU reset) as an event on the source and reacquire, so a
  recording of several hours continues through it.
- Done when: a 4K monitor is acquired at 60 frames per second with low CPU, frames carry changed
  rectangles and timestamps, the pointer is delivered separately from the pixels, and acquisition
  resumes by itself after a lock screen, an elevation prompt and a display mode change.
- Related: app.capture.011, app.capture.034, platform.portability.098, std.screen.002

### platform.portability.098 — An occluded window cannot be captured

- Next: add Windows.Graphics.Capture (WinRT activation, a frame pool on Direct3D 11) as a window
  source behind platform.portability.097, without the capture border where the system allows it.
- Done when: a window covered by another one, or partly off screen, records its own content.
- Related: platform.portability.097, std.screen.002

### platform.portability.099 — No Media Foundation bindings

- Evidence: software H.264 and full-band AAC-LC encoders now exist in Swag without an external
  codec dependency. Windows also offers Media Foundation transforms, including vendor hardware
  encoders, but no binding is needed to produce a playable software recording. Current 4K I_PCM
  performance does not yet prove whether a fully optimized software encoder can meet 4K60.
- Next: measure realistic 4K60 capture after software H.264 transform coding, rate control and
  conversion optimization. Bind only the native encoder subset if the required capture profile
  cannot be met in software; report systems without those media features explicitly.
- Done when: any required native path can be configured and driven from Swag with a clear failure
  where unavailable, while software encoding remains usable without it.
- Related: std.video.015, std.audio.015

### platform.portability.100 — No camera source

- Next: add camera enumeration and capture (Media Foundation source reader on Windows, V4L2 or
  PipeWire on Linux) delivering timestamped frames.
- Done when: a caller can list cameras, choose a resolution and receive frames with timestamps on
  both platforms.
- Related: app.capture.036, platform.portability.099

### platform.portability.102 — The notification-area icon cannot notify on Linux

- Evidence: `Gui.Surface.showTrayMessage` shows a notification through `Shell_NotifyIconW` on
  Windows and does nothing on Linux. Swag Capture uses it to say that it keeps running behind
  its icon once its hub or its window is closed, so a Linux reader is not told.
- Next: send the notification through the `org.freedesktop.Notifications` D-Bus service, and
  fall back to the XEmbed `_NET_SYSTEM_TRAY_OPCODE` message only where no service answers.
- Done when: the same call shows a silent notification on a Linux desktop with a notification
  service, covered by an integration test, and stays silent without one.

### platform.portability.101 — Linux has no screen recording or sound capture source

- Evidence: on an X11 session (Xvfb, Openbox, Picom) Swag Capture records an animation of an
  area, stops it from its pill, and opens it in the editor with its timeline; the clipboard file
  list round-trips through an independent client. Each frame is still read from the X11 root,
  which also records any window over the area, and under software OpenGL the frame grab starves
  the event loop enough to answer Stop a few seconds late.
- Next: add the XDG desktop portal with PipeWire for Wayland screen and window recording, X11
  shared-memory grabbing with damage, and PipeWire or PulseAudio capture and monitor sources for
  std.audio.011 and std.audio.013.
- Done when: a Linux session records an animation, then a window with its sound, under X11 and
  under Wayland.
- Related: platform.portability.097, std.audio.011, std.audio.013, std.gui.063,
  std.screen.003

### platform.portability.103 — Optional SIMD beyond the baseline has no shared dispatch contract

- Evidence: the supported compiler/runtime baseline is x86-64-v3 and startup rejects older
  hosts; there is no lower-ISA build mode. Standard modules still have no common contract for
  optional features beyond that baseline.
- Next: add authoritative optional-feature queries and function multiversioning so a module can
  select a baseline or richer implementation without duplicating dispatch. A lower-ISA product
  target would require a separate explicit baseline decision.
- Done when: dispatch is cached, testable with a forced feature ceiling, works in JIT and native
  builds, and one runtime or codec kernel selects a measured optional-feature variant while retaining its
  baseline implementation.
- Related: compiler.codegen.019, compiler.codegen.020.
