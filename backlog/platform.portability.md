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

- Progress: Linux Hardware.processorCount reads the calling thread's affinity mask, with a
  conservative one-processor fallback when unavailable; bandwidth quotas are explicitly outside
  that count. Hardware.macAddress enumerates getifaddrs, skips loopback and unsupported address
  lengths, and returns the first nonzero six-byte address in native enumeration order. Its
  documentation excludes a stable machine-identity guarantee. Process/thread IDs now use getpid
  and gettid, and the public Thread test checks its identity through Env.Process.currentThreadId.
- Validation: 15 raw Linux binding tests pass JIT/native, including native interface indices,
  linked-list layouts and affinity-buffer canaries. A separate importing module passes two tests
  in both modes, including the anonymous native address union, and its executable exits 37.
  The public hardware case and three thread lifecycle cases pass in JIT/native, including CPU
  affinity count, hardware address shape and process/thread identity queries.
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

- Progress: Linux gamepads share readable evdev enumeration in event-node order. State queries
  read key bits and advertised axes, normalize full signed ranges without overflow, invert stick
  Y, map standard X/Y and RX/RY sticks, Z/RZ triggers, and HAT0/button D-pads; optional controls
  are neutral. No device-specific remapping/deadzone database or atomic multi-ioctl packet is
  promised. Hotplug/permission changes may renumber indices; write access never renumbers them.
- Rumble: writable FF_RUMBLE devices retain one effect/file owner per slot. Finite speeds clamp
  to 0..1; left/right map to native strong/weak motors. Zero stops and closes, native update errors
  release the prior effect, inode/device changes replace stale ownership, and module shutdown
  closes every retained descriptor. Native calloc/free storage does not borrow a caller allocator.
  Zero replay length requests continuous playback, matching the Linux ff-memless implementation;
  real hardware behavior, driver differences, disconnection and cleanup remain unverified.
- Validation: a C probe of linux/input.h confirms input_absinfo/input_event (24 bytes), ff_effect
  (48 bytes, union offset 16, replay 10, trigger 6) and ioctl request values. All 24 raw bindings
  tests pass JIT/native; the last test also passes through a separately published/imported module.
  This covers layout, rumble union representation, rejected /dev/null ioctls and canaries, not
  successful hardware acquisition or motor behavior. No /dev/input or /dev/uinput is exposed.
  Public normalization and missing-index cases pass in JIT/native; real devices remain unavailable.
  Raw API HTML has no broken anchors/duplicate IDs; the existing errno synthetic-name finding remains.
- Next: validate real or uinput devices for connect/disconnect, permissions, calibration,
  optional controls, rumble replacement/stop/shutdown and focus loss. Keep normalized state and
  policy common.
- Done when: The chosen second host acquires keyboard and gamepad state into the normalized input model, including connect/disconnect and focus loss, with platform tests that keep native device identifiers out of common callers.

### platform.portability.057 — No second-platform GUI packaging

- Next: package the GUI runtime and native dependencies for the chosen second platform.
- Related: platform.portability.050, platform.portability.058
- Done when: A packaged GUI application on the chosen second platform launches on a clean target with its renderer, fonts, and native dependencies present, and a packaging smoke exercises open, render, and close.

### platform.portability.058 — Finish Linux mixed-script font validation

- Progress: `FontFamily.createTypeFace(name, style)` now loads selected Linux families from the
  shared catalog, accepting typographic and legacy names and preserving collection indices.
  Missing bold/italic traits use separately cached typefaces with independent glyph workspaces;
  ordinary file loads remain unchanged. A separate consumer passes four tests in JIT/native,
  including real Open Sans legacy aliases and DejaVu synthetic styles. An installed-family
  integration test passes in both modes, and Pixel's 92 native golden tests remain green.
- Owned Linux family and face descriptors now expose actual file paths, collection indices
  and style metadata through `enumerateSystemFonts` and `findSystemFont`. Two focused cases pass
  JIT/native, and the complete Pixel API page passes its structure and link audit.
  Native GUI application, surface, cursor and clipboard services now execute on X11; Capture
  and Vault startup smokes render their font consumers successfully.
- Validation: the multilingual HTML golden now owns small, renamed SIL-licensed CJK and
  outline-emoji subsets and disables system fallback for that fixture. Its reviewed reference
  changed only around those runs and their spacing; all 85 HTML cases pass with the existing
  tolerance. This replaces the old implicit dependence on Windows fallback fonts.
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

- Native groundwork: glibc spawn attributes/file actions and signal-set layouts, posix_spawn(p),
  waitpid/status macros and kill are now bound. The 21 raw Linux tests pass in JIT/native, including
  exact empty/spaced/quoted/backslash/UTF-8 argv, explicit environment, child working directory,
  redirected output, direct spawn error codes, nonblocking wait, signal exit and single reaping.
  A separate module executes both process probes through the published opaque types/functions.
  Public owner validation below additionally exercises duplex draining and timeout/drop behavior.
- Process context: Linux currentEnvironment copies glibc's current environ table, preserving
  case and distinguishing snapshot mutation from process mutation. The table's address is
  resolved from the current image; its mutable contents remain caller-synchronized native data.
  currentExecutablePath reads /proc/self/exe with a growing buffer and retains Linux's deleted
  image spelling. Procfs failures propagate. The 22 raw tests pass JIT/native and an imported
  consumer, including truncated readlink without a terminator, image inode identity, missing
  procfs links and environ/getenv agreement. The public snapshot/ownership case passes JIT/native.
  An isolated native peer checks live setenv/unsetenv changes, case-sensitive names, empty versus
  absent values and the stability of snapshots taken before later mutations.
- Owner implemented: posix_spawnp receives owned argv/environment strings and native file actions
  for redirection/chdir. Pipe sources are normalized above fd 2; only parent endpoints are
  nonblocking, and all intermediate descriptors close on failure. Linux rejects raw native
  arguments, pre-exec affinity and tree accounting before launch. Search uses the parent PATH.
  Waits own waitpid status, map signal exits to 128+signal, and retry EINTR. Input writes drain
  both outputs on backpressure and block/consume only a newly generated SIGPIPE on the caller's
  thread; no process-wide signal disposition changes. kill sends SIGKILL without inventing an
  arbitrary Windows exit code. Query supportsResourceMeasurement before requesting accounting.
- Lifecycle implemented: ordinary close transfers a live child to one lazily started reaper;
  it neither kills nor waits. Native calloc/free state outlives the caller's allocator. Core
  shutdown joins queued children before unloading worker code or deleting the sandbox root.
  A destructor after shutdown waits synchronously. This intentional Linux shutdown constraint
  is documented; owner operations must be serialized and external child reaping is prohibited.
- Validation: 23 raw tests pass JIT/native, including per-thread SIGPIPE preservation/consumption,
  EPIPE, zeroed native allocation, independent pipe endpoint flags and FIONREAD. The last probe
  also passes through a separately published/imported Linux module and native consumer exit 37.
  Eight Linux public process tests cover context, argv/env/cwd/status, 256 KiB duplex I/O,
  timeout/kill, broken stdin, close/reaping, unsupported options and simultaneous output/error.
  All eight public cases pass in JIT/native, including natural child reaping after close.
  A native child with descriptors 0, 1 and 2 closed passes a public stdin/stdout/stderr pipe
  roundtrip, confirming that pipe endpoints are moved above the standard descriptor range.
  A continuously writing child exercises the finite wait deadline in JIT and native execution;
  a child that exits while a grandchild retains its output pipes does not wait for pipe EOF.
  All ten cases in the public process file pass in both modes.
  A separate native stress peer opens 64 processes with three redirected streams and attempts
  64 missing executables; its /proc/self/fd count returns to baseline after owner close.
  A native peer stops Core's reaper before closing a live process owner; close waits and reaps
  that child synchronously, and the later Core shutdown remains safe.
  A dynamically loaded module also closes a live child before unloading; the consumer observes
  the child leave procfs while its shared Core dependency keeps the reaper alive. Both native and
  JIT consumers now exercise that unload boundary with a live child.
  Windows shared-policy checking reaches only the known log/logf cross-host foreign failures.
  Raw API HTML has no broken anchors/duplicate IDs; the existing __errno_location synthetic-name
  audit finding remains. These checks do not prove the reaper's broader native lifetime.
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
- Next: exercise kernel-overflow stress, remaining interrupted operations and permission races; run the remaining
  common filesystem/stream/mapping cases, and compare Windows ownership behavior.
- Done when: The chosen second host passes the common directory, file, stream, metadata, path-state, and mutation contract suite, including partial I/O, links, permissions, and error mapping.

### platform.portability.034 — Finish the Linux thread lifecycle backend

- Evidence: Linux sleep uses an absolute CLOCK_MONOTONIC deadline and retries EINTR without
  extending it; yield uses sched_yield. Raw bindings pass JIT/native lower-bound timing and
  invalid-timespec tests. Public Linux thread lifecycle tests now execute through complete Core.
- Progress: the pthread backend creates a gated thread, publishes its kernel TID before init
  returns, starts once, joins, probes completion with pthread_tryjoin_np, and keeps its original
  allocator until the owner closes it. A successful nonblocking join is remembered so wait
  releases the owner without joining twice. Common init now cleans up a priority failure without
  running the user body and always applies priority when a Thread value is reused.
- Priority contract: Linux maps the five levels to per-thread nice offsets +2, +1, 0, -1 and -2
  relative to the creator's inherited baseline, clamped to [-20, 19]. Raising priority can fail
  with host permission errors; the public level changes only on success. Exited identities are
  retired before kernel reuse, and real-time policies are left unchanged.
- Validation: 14 raw Linux tests pass in JIT/native, including gated C callbacks, distinct kernel
  identities, EBUSY from a live nonblocking join, scheduler validation and join result publication.
  Seven public Core thread cases pass in JIT/native with DevMode and Release compilers,
  covering nice values, inheritance, permission failures, exited identities, reuse,
  completion and waits. An eighth DevMode case rejects a second start, keeps its owner
  joinable, and runs the body once across 64 reuse cycles in JIT/native. Four common
  thread/timer cases also pass in JIT/native for context inheritance, one-shot and periodic behavior. A native 65-thread stress
  case crosses the 64-handle wait batch and verifies every owner is released. Windows execution is unavailable.
- Next: exercise thread-creation failures under resource pressure and additional lifetime stress,
  and decide whether to extend Linux priority support.
- Related: platform.portability.035
- Done when: The chosen second host passes common creation, join, yield, sleep, identity, and priority tests, including failed start and orderly shutdown, without duplicating lifecycle policy in its native leaf.

### platform.portability.037 — Validate the Linux timer backend

- Progress: the shared timer worker now owns monotonic deadlines, serialized callbacks, missed-
  period coalescing, cancellation wakeup and join-before-free. Linux supplies pthread creation
  and join; Windows supplies CreateThread and wait/close. The original allocator is retained
  until the worker has stopped, and callback context isolation remains common.
- Validation: both public lifecycle cases pass in JIT/native, covering cancellation before a long
  first deadline, serialized periodic callbacks, waiting for an active callback and repeated release.
  Windows-target analysis stops at the refusal to JIT-load target Windows log/logf; native Windows
  execution is unavailable.
  Four common thread/timer cases also pass JIT/native, including inherited callback context.
- Next: validate the Windows leaf and stress shutdown/concurrent-owner behavior.
- Related: platform.portability.029
- Done when: The chosen second host passes the common one-shot, periodic, cancellation, wake, and shutdown timer tests while keeping scheduling policy in common code.

### platform.portability.038 — Finish Linux environment services and validation

- Progress: Linux keeps runtime argv, looks up case-sensitive environment variables, and resolves
  special directories. TMPDIR is made absolute; HOME falls back to reentrant getpwuid_r. XDG base
  directories reject relative overrides. Quoted absolute/$HOME user-directory assignments are
  parsed as data, including escaped literal characters and last valid assignment precedence;
  commands and other variable expansion are not executed. Missing configuration uses documented
  conventional subdirectories. Shared media directories explicitly report an unavailable path.
  Sandboxed queries retain the common per-kind scratch-directory redirection.
- Validation: 17 raw Linux tests pass JIT/native, including passwd layout/canaries, caller-owned
  string storage and ERANGE. A separate importing module passes the same user-database call in
  both modes and its real executable exits 37. Three public environment cases, the XDG parser case
  and the sandbox-path case pass JIT/native. Empty and relative HOME/XDG overrides are exercised
  in separate invocations. Validate a path before calling isRooted: it requires a valid nonempty
  path, so the previous order asserted on empty variables or zero bytes in configuration data.
  Message-locale lookup now follows LC_ALL, LC_MESSAGES and LANG precedence, omitting encoding/
  modifier suffixes and mapping separators to hyphens. C/POSIX and malformed names return empty.
  Two parser/precedence cases pass JIT/native; a separate archive consumer passes seven controlled
  environment configurations in both modes. No process-wide C locale is changed.
- Desktop actions: `openFile` and `openUrl` launch `xdg-open` through separate argument values,
  without shell parsing or inherited streams. Relative file paths become absolute without
  changing symlink semantics. The result describes launcher startup, not later handler success;
  missing launchers and invalid inputs return false. JIT/native tests cover exact Unicode and
  metacharacter transmission, relative/absolute paths, invalid inputs and a missing launcher.
  A separate importer also exercises the installed `xdg-open` with a controlled BROWSER handler
  in both modes. `showInFileExplorer` sends an encoded local file URI to FileManager1.ShowItems
  through `gdbus`, waits for acknowledgement and bounds the request to approximately two seconds.
  Controlled launcher checks and an importing consumer on a private D-Bus session pass JIT/native:
  Unicode/reserved characters, accepted/rejected requests, missing service and tools, timeout,
  and request-process cleanup. Interactive desktop presentation remains unverified.
- Application chooser: `openFileWith` now uses the optional session OpenURI portal through
  libsystemd. It passes a real file/directory descriptor and `ask=true`, refuses portal versions
  below 3, bounds each D-Bus exchange to two seconds and retains the connection until Core
  unload so acknowledged dialogs survive the API return. A native integration on a private
  bus passes real descriptor contents, directory identity, repeated requests, sender lifetime,
  old-version refusal, explicit rejection, timeout/recovery, missing library/bus, invalid targets
  and sandbox refusal. Core API generation covers 2,099/2,099 declarations and 388/388 members;
  the isolated Core-only output still lacks the existing linked Gui page. No default-application
  fallback substitutes for the chooser. Sandboxed
  target applications receive no writable document-portal grant.
- Next: validate chooser presentation on a real desktop. The
  return value reports request acknowledgement, not eventual user selection or application launch.
- Related: platform.portability.010, platform.portability.015
- Done when: The chosen second host provides argument, environment-variable, locale, special-directory, and generic desktop-action operations through the portable API, with explicit unsupported results and focused contract tests.

### platform.portability.040 — Validate Linux sandbox enforcement and startup

- Progress: Linux early lookup uses runtime argv through common name/value matching. Existing
  path prefixes are canonicalized with realpath before missing suffixes are normalized, preserving
  symlink/parent semantics; failed resolutions contain nothing. Common containment preserves Linux
  case and backslashes, retains Windows normalization, and correctly includes descendants of a
  filesystem root. Windows canonicalization now fails closed instead of using the literal input.
  Reparse-point scanning is shared. Unlinking a final file/directory link checks its authorized
  parent without following that final link; writes and traversal through parent links still fail.
  Shared tests distinguish Windows delete-sharing exclusion from POSIX open-descriptor lifetime.
- Validation: 18 raw binding tests pass JIT/native, including realpath allocation/free, a link
  followed by '..' and ELOOP. Public tests for argv matching, case, root containment, invalid paths,
  escaped writes/deletes and safe link removal pass in the public Linux integration case in
  JIT/native. An isolated native peer verifies arming before a later #init and #premain and refuses
  an outside write without creating its target. A separate native executable importing Core
  sees the sandbox already armed in its own #init and #premain; native Windows validation is unavailable.
- Next: run the remaining common sandbox and filesystem conformance cases.
  The guards protect Core's operations; they are not an OS security boundary for arbitrary native
  calls and do not make path checks and subsequent mutations atomic against concurrent renames.
- Related: platform.portability.038, platform.portability.010
- Done when: The chosen second host applies sandbox restrictions before user code and imported native modules run, rejects forbidden filesystem and process actions in integration tests, and reports unsupported enforcement explicitly.

### platform.portability.001 — Complete the Linux repository test gate

- Evidence: `tools/linux-tests.py all` covers compiler suites, workspace fixtures, standard
  modules, examples, applications and reference through the shared Windows/Linux command
  builders. Complete execution still exposes GUI runtime and platform-assumption failures.
- Progress: resumable checks now report failure through the shared runtime context, including
  checks raised inside imported native libraries. Linux timeouts stop detached test descendants,
  and isolated campaigns reuse dependencies and release inactive file cache on admission waits.
- Validation on the synchronized GPU-resource changes: all 4,049 native-language cases pass
  in JIT and native execution. The complete GUI module passes 965 of 969 cases; PDF text and
  viewer cases pass after standard-font metric/style repairs. The HTML failure then passes in
  its 85-case focused run with pinned fixture fonts. Three recorded antialiased contour
  differences remain on Mesa software rendering: confirmation focus (8 pixels, maximum channel delta 4), floating sheet (4 pixels,
  delta 3), and property-menu separator endpoint (1 pixel, delta 20). Preserve their strict
  failure status while identifying the geometry, coverage, or driver boundary.
- Next: fix remaining failures at their owning boundaries and complete one uninterrupted
  campaign on the synchronized checkout.
  Keep functional, golden and stress coverage, golden expectations and failure status.
  Select native `integration.*` families separately with their service/hardware prerequisites.
  Prioritize this gate before debug-record expansion or unrelated compiler capabilities.
- Done when: one documented Linux command executes every applicable repository test family,
  produces a complete report with no unexplained failure or unexecuted stage, and rejects
  accidental Windows dependencies in neutral sources.

### platform.portability.008 — Validate the argv-first process API

- Progress: StartInfo.arguments is now a borrowed nullable slice of strings; null/empty means
  no arguments after argv[0]. startProcess/runProcess accept separate argument values, and
  Windows serializes them with the existing C-runtime quoting algorithm. Programs with their own
  grammar, including cmd.exe tests, explicitly use the Windows-only nativeArguments escape hatch.
  The common entry validates zero bytes, empty required names, environment names and conflicting
  argument forms before calling the host leaf. Linux explicitly rejects nativeArguments.
- Migration: Scope thumbnails, Pixel child tests, Vault's
  visibility probe and debugger launch now pass vectors without manual quoting. This is a source
  API change: callers passing a command-line string must pass a vector or explicitly choose
  StartInfo.nativeArguments for Windows. No shell is inserted implicitly.
- Validation: raw Linux spawn probes preserve exact argv in JIT/native and an imported consumer.
  Whole-Core test/doc compilation succeeds. Windows semantic/test compilation on this Linux host
  stops at the known foreign log/logf imports.
  Public Linux process cases now pass JIT/native with exact empty, spaced, quoted, backslash and
  UTF-8 child arguments, and the separate importer executes through complete Core. Native Windows
  quoting and focused Scope/Pixel/Vault consumers still need execution on supported hosts.
- Next: run the Windows quoting path and focused Scope/Pixel/Vault consumers on supported hosts.
- Done when: StartInfo accepts an argument vector as its normal API; Windows quoting and Unix
  direct argv preserve empty, spaced, quoted, and backslash-containing arguments in
  child-process tests, with any raw command-line form explicitly named.

### platform.portability.011 — Process-tree resource accounting has no portable capability contract

- Progress: Process.supportsResourceMeasurement reports true on Windows, false on Linux. Linux
  rejects StartInfo.measureResources with ENOTSUP before launch; unmeasured resources remain zero.
  The public Linux capability/rejection case passes in JIT/native.
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

- Progress: input validation, start/run overloads, close/drop dispatch, paired output draining,
  wait loops, real monotonic timeout budgets and portable termination dispatch live in common
  process.swg. Ordinary drains cap each stream at 64 KiB; final drains snapshot available bytes
  so descendant-held pipes cannot make waiting for the direct child wait for EOF. Windows and
  Linux supply spawn, wait/status, stream operations and native lifetime/reaping.
  Linux writes service captured output during pipe backpressure; Windows input writes remain
  blocking and need the equivalent duplex behavior. Eight public Linux lifecycle cases pass
  JIT/native, including duplex stdin and simultaneous stdout/stderr output beyond pipe capacity.
- Evidence: the process value, environment map, recorded-status accessors, and convenience
  `startProcess`/`runProcess` overloads already live in common `process.swg`.
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

### platform.portability.051 — No second-platform monitor and DPI integration

- Progress (Linux): Core enumerates active RandR 1.5 monitors, clips the current EWMH desktop
  work area to each, and falls back to real root-screen geometry when RandR is unavailable.
  Extension presence is checked before any RandR opcode: sending a version query to a server
  without RandR otherwise closes the entire XCB connection.
  Missing displays return an empty array. Coordinates are explicitly physical pixels with scale
  one; physical dimensions are not used to invent scaling. Xvfb JIT/native coverage passes.
- Next: implement monitor enumeration and per-monitor scale for the platform whose surface exists
  under platform.portability.050.
- Related: platform.portability.050, platform.portability.084, platform.portability.052, platform.portability.056
- Done when: The chosen second-platform surface enumerates active monitors, uses the correct per-monitor scale during open, move, and resize, and updates placement after topology or scale changes without exposing native monitor handles.

### platform.portability.052 — No second-platform keyboard routing

- Progress (Linux): Core polls X11 keymaps and keyboard mappings, exposes canonical keysyms as
  VirtualKey values, maps common modifiers and the first three mouse buttons, and snapshots basic
  Latin-1/Unicode characters with Shift/Caps Lock in the first group. Pointer query/warp is also
  implemented. Standard PC keypad NumLock/Shift selection and held-key release identity pass
  real XTEST integration in both polling and GUI paths. Extra buttons, additional groups,
  IME and broader input-language routing remain pending;
  polling snapshots are separate native requests, not one atomic input sample. GUI XKB
  composition now sends every committed Unicode scalar as a separate portable character event;
  real XTEST input covers ordinary, dead-key and multi-scalar compose sequences in JIT/native.
  XKB map notifications now reload the keymap and state together; an active GUI accepts a
  remapped key while preserving physical transition events in JIT/native. A key held across
  another remap retains its old release identity and uses the new identity on the next press.
  The existing XTEST keypad case remains green in both modes.
  Raw key/button/motion/crossing/focus packets now match xcb/xproto.h sizes and offsets.
  The opt-in XCB suite round-trips all nine event kinds through SendEvent, preserving signed
  coordinates, masks and focus fields in JIT/native. A separate importer checks exported layouts;
  these are protocol tests, not normalized input routing or real-device key transitions.
- Next: validate repeated keys, modifier transitions and full input-language changes
  through portable keyboard events.
- Related: platform.portability.050, platform.portability.085, platform.portability.054
- Done when: The chosen second-platform backend reports physical key, modifier, repeat, and layout changes through portable keyboard events, with tests covering key-down/up, repeated keys, and text input independently.

### platform.portability.056 — No second-platform system-theme notifications

- Next: translate the platform's live theme and high-contrast changes into the portable settings
  event.
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

### platform.portability.085 — Input-language changes are ignored

- Owner: std/gui
- Evidence: `gui/src/surface.win32.swg` handles key and character messages but has no `WM_INPUTLANGCHANGE` route.
- Next: handle the platform input-language notification and update keyboard-layout-dependent state.
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
- Related: compiler.safety.006

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

### platform.portability.050 — No second-platform surface and presentation backend

- Progress (Linux): optional XCB/X11 protocol bindings now cover checked window requests,
  events, properties, pointer/keyboard snapshots and RandR 1.5 monitor queries. Three opt-in
  `integration.xcb` tests pass in JIT and native ELF on an isolated Xvfb display, including
  a separate importing module, BadWindow recovery and malformed-display failure. C headers
  independently confirm the layouts. Libraries are dynamically loaded, so headless consumers
  do not acquire a mandatory desktop dependency.
- Core progress: native-allocated window ownership, owner rebinding after moves, checked create/
  resize/position/show/hide/focus/close requests, UTF-8 titles and window-manager hints, bounded event dispatch,
  close-request versus destruction semantics and offscreen realization are implemented. Two
  public cases pass JIT/native under Xvfb, covering moved owners, resize callbacks, monitor/pointer
  queries, WM_DELETE_WINDOW, repeated close, external destruction and closing from a paint callback. A separate opt-in
  case validates neutral queries and failed creation without a display. Explicit paint events
  also work for fully offscreen windows, where ClearArea would produce no Expose event.
  The lazy connection retains optional RandR and XFixes libraries until disconnect, avoiding extension-cache
  identities accumulating from repeated unload/reload. Window operations stay on the creating
  thread; module shutdown invalidates owners before releasing native state. Connection-loss,
  module-unload stress and window-manager integration still need dedicated execution.
  `WindowCallbacks.onFocus` now routes X11 focus gain/loss on the owning thread. Two native/JIT
  tests change real Xvfb focus between windows, move an owner with a queued event, and close from
  the callback. A separate importing module also passes both modes. The common callback and
  Windows dispatch adapter are shared; actual GUI focus policy remains part of GUI integration.
  Public placement, hide and focus requests enforce open-window and owning-thread contracts.
  Xvfb tests cover actual geometry and visibility, hidden-window focus rejection, moved owners,
  callbacks closing their owner and a separately linked importer. Placement remains a native
  request; decorated window-manager policy and complete GUI integration remain unvalidated.
  Core cursor visibility uses optional XFixes 4 and a serialized process-wide show/hide counter.
  Only zero crossings issue native requests; a rejected request leaves the counter unchanged.
  Missing displays or extensions are neutral, and extension presence is checked before negotiation.
  Five public desktop cases pass JIT/native: the two window cases, cursor nesting and BadWindow
  recovery, missing-display neutrality, and a server with RandR/XFixes explicitly disabled.
  The disabled-extension case failed before the presence guard by losing its XCB connection.
  Cursor visibility on screen is not visually measured, and a real window manager remains untested.
  Ogl now supplies an EGL/XCB OpenGL 3.3 compatibility context owner matching Core window visuals.
  Five framebuffer/context/failure cases pass JIT/native under Xvfb with Mesa software rendering,
  including context creation on a rendering worker and independently owned surfaces sharing GL objects.
  The stable XCB render descriptor survives moving its Core window owner; native desktop tests cover
  that identity and its invalidation on close in JIT and native execution. Separate shared-library and companion-archive consumers
  render and read back pixels in both modes; the Ogl API page passes its structural/link audit.
  Pixel now has a Linux EGL adapter: one renderer-owned context outlives its individual window surfaces.
  Eight Pixel integration cases pass JIT/native: render-worker presentation, asynchronous cropped/strided
  readback, render-target survival after closing the first of two windows, clipping, SVG alpha, sampling,
  padding and backdrop effects. Six ordinary native renderer/thread tests also pass, including failure
  retirement. All 92 Pixel golden tests pass natively without changing references. Native
  application startup, rendering and close now pass for Swag Capture and Swag Vault
  under Xvfb/Openbox, with captured window pixels inspected. Capture reports unavailable
  shortcuts when the window manager owns Print/Alt+Print; Ctrl+Print is exercised by real XTEST
  input after canonical Linux key mapping was corrected. Scope now also passes native startup,
  WAV loading, waveform display and PCM playback through FAudio's SDL disk device. Broader
  application workflows and physical desktop/device validation remain.
  GUI application/surface/cursor services, XKB input and map updates, clipboard selections and XDND/XDS are
  implemented. Thirteen JIT/native cases compare complete window pixels under Xvfb/Openbox
  with a compositor and exercise real XTEST events, XSettings, headless rendering, clipboard
  UTF-8/PNG/INCR and independent drag/drop peers. These fixtures validate GUI font consumers;
  they do not replace the full application workflows.
  An isolated Xorg dummy server also passes clipboard owner exit and empty text roundtrips
  against an independent client in JIT/native. The toolkit-owned file dialog selects existing
  Linux names containing colons and Unicode, proposes new paths, rejects invalid selections and
  returns cancellation on a native X11 surface in JIT/native.
  Native artifact work remains in .093.
  Nine Ogl JIT/native cases now cover independent XCB connections, shared contexts and resources,
  worker-thread contexts and pbuffer lifetimes. Two surfaceless cases pass without a display.
  Core still has no mandatory GL/EGL dependency. Physical GPUs and native Wayland remain open.
- Evidence: the filenames already expose most of the seam: `surface.win32.swg`,
  `application.win32.swg`, `clipboard.win32.swg`, `dragdrop.win32.swg` and `cursor.win32.swg`, with
  shared Windows clipboard text conversion in `nativetext.win32.swg`. The retained tree, layouts,
  themes, controls and the toolkit-owned file dialog are platform-neutral. These leaves identify
  mechanisms to replace; their file count is not a porting plan.
  Core provides opt-in independent window lifetimes through `WindowOptions.stopLoopOnClose`
  and `WindowCallbacks.onCloseRequest`. GUI can defer native close requests until renderer borrows
  are retired and explicitly decide when its application quits; there is no implicit last-window
  shutdown. Existing WindowLoop consumers retain their default close behavior.
- Next: validate complete application workflows and physical desktop/GPU behavior, finish dynamic
  input-language changes and investigate connection-loss/module-unload stress. Native Wayland,
  IME composition and accessibility remain distinct capabilities. The X11 GUI uses explicit
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

### platform.portability.080 — Bare `.swgs` execution has only a Windows shell contract

- Evidence: `tools/setup.bat` registers the checkout's `bin/` directory and `SWAG_PATH` for the
  current user. It no longer claims a file association; `.swgs` examples continue to require an
  explicit compiler command, while tools launch as `.bat` files.
- Next: define shell and desktop-launch integration per host without making Windows file
  associations the portable script contract. Machine-wide mutation remains explicit and opt-in.
- Done when: setup reports whether bare execution is supported for the current shell and either
  configures it safely or prints the exact remaining elevated step; a fresh `cmd.exe` and
  Windows PowerShell 5.1 session execute a representative bare `.swgs` script according to that
  contract; a supported non-Windows shell either executes the same representative script
  through its documented launcher/shebang path or reports bare execution as unsupported with an
  exact command; existing double-click behavior remains intact; and moving the checkout and
  rerunning setup refreshes stale interpreter paths, and removal instructions undo installed
  associations.
- Related: compiler.core.016

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

- Progress: `time/timer.worker.swg` now owns one worker per timer, monotonic deadlines, serialized
  periodic callbacks, skipped missed periods, cancellation and join-before-free. Both native
  leaves only create/join a thread. The public contract states that distinct timers may run
  concurrently while a single timer never overlaps its own callbacks; this replaces the former
  Windows timer-queue behavior that allowed overlap.
- Two public lifecycle and four common thread/timer cases pass Linux JIT/native for cancellation,
  active callback release, one-shot/periodic behavior and context inheritance.
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

- Owner: the `net` module from std.core.001.
- Evidence: Windows and Linux leaves implement blocking IPv4 TCP behind the same stream and
  listener owners. Linux uses close-on-exec sockets, suppresses SIGPIPE per send, retries interrupted
  transfers/accept, and completes interrupted connects through poll and SO_ERROR. Failed acquisition
  closes its socket. The two ordinary TCP tests and four tagged Linux integration cases pass in
  JIT/native, covering loopback, EOF, close/drop, descriptor inheritance flags, error preservation,
  SIGPIPE suppression and repeated failed bind/connect without leaked sockets.
  A separately linked Net consumer passes in JIT/native, including short reads and drop/EOF.
  Generated Net API docs have 25 documented declarations and 18 documented members, with no
  unresolved links. The existing Windows socket cleanup is preserved by inspection; Windows
  execution has not been rerun for this change.
  Linux HTTP/HTTPS now uses a lazily loaded libcurl backend with strict target and proxy TLS,
  bounded bodies/headers, preserved request-target bytes, explicit redirects and whole-transfer
  deadlines. Six ordinary HTTP tests, seven direct HTTP/TLS cases, three proxy scenarios and a
  separate importing consumer pass in JIT/native execution. The generated Net API has 26 documented
  declarations and 18 documented members, with no unresolved links. IPv6, datagram transport,
  resolver APIs and cancellation remain absent from the common transport surface.
- Next: extend the address and ownership contracts for IPv6, UDP and host/service resolution. Add cancellation and interrupted-connect integration coverage;
  keep native handles and error translation inside host leaves, and add readiness only after
  the common concurrency contract is decided.
- Done when: both host backends pass the same loopback, partial-transfer, cancellation,
  resolution-failure, and handle-lifetime tests without exposing native types to callers.
- Related: std.core.001, std.core.002, std.core.003, std.core.004, language.parallelism.001.

### platform.portability.081 — Foreign vector ABIs are unavailable

- Intent: support explicitly selected platform vector ABIs for foreign declarations where the ABI
  is stable, while continuing to reject an ambiguous bare C-vector contract.
- Next: choose the first explicit foreign vector-ABI annotation and the C/C++ fixtures for
  Windows x64 that pin its parameter and return passing.
- Done when: supported Windows x64 and one non-Windows target's vector parameters and returns
  interoperate with C/C++ fixtures, unsupported conventions fail semantically, and the contract is
  documented per target.
- Related: cpu.simd.002.

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
- Related: std.audio.007

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

- Evidence: `src/screenshot/screenshot.win32.swg` and the GDI dependency are the whole platform
  boundary on the capture side. The editor, the forms, the library, and the serialization are
  already portable.
- Next: validate the Linux X11 screen/region/cursor backend and window metadata queries, then
  exercise the complete capture application with a compositor and window manager. Account for
  native Wayland capture through the desktop portal rather than reading the XWayland root alone.
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

