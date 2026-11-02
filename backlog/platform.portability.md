# Operating-System Portability Backlog

This is the sole backlog for porting any part of Swag to another operating system. It covers
`bin/runtime`, standard modules, shipped applications, compiler tooling, target ABIs, packaging,
and desktop integration for Linux, macOS, and future hosts.

It also owns every Windows-specific type, protocol, service, policy, or assumption that portable
code must stop exposing. The owning module still implements the change, but the entry stays here
with its target backends and prerequisites so one port cannot be scattered across domain files.

The checked dependency layers and their path ownership are defined in
[bin/PORTABILITY.md](../bin/PORTABILITY.md).

Current Linux validation: the last complete C++ run passed 1,754 tests. The raw Linux module
passes 24 system tests and three opt-in XCB tests in JIT and native ELF. Whole Core now builds
core.so and compiles its test sources. Public suites pass in JIT/native for memory (2), filesystem
(8), environment (3), hardware (1), native libraries (2), threads (3), events (5), timer lifecycle (2), processes
(8), watchers (10), sandbox paths (1), evdev normalization/absence (2), crypto (5), calendars/clocks
(31), XDG parsing (1), common thread/timer context behavior (4), and the initial X11 desktop
(5, including an unavailable display and disabled extensions). The XDG public path case also passes with empty and relative
HOME/XDG overrides. These are focused boundary suites, not the entire Core test inventory.
Pixel passes 92 native golden tests after synchronizing master and adding collection-face
cache keys. Its four direct typeface tests pass in JIT and native execution. The complete golden
campaign still stops before GUI and application tests because Linux GUI services are incomplete.
Core API generation succeeds: all 2,075 declarations and 378 exposed members have comments;
Linux still lacks the referenced Debugger/openUrl surface, and the separate GUI API page is not
built in this probe. Those three documentation references remain unresolved.

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
- Next: validate electric-mode faults, cross-module and fork ownership.
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

### platform.portability.042 — Validate the Linux console backend

- Evidence: Linux byte output retries interrupted/partial writes. Prompt reads through the first
  newline without consuming the next line. ANSI colors are restricted to a terminal with a
  nonempty TERM other than dumb, and changed colors are reset at module drop. Redirected output
  receives no color escapes. Whole Core compiles; public console execution remains unverified.
- Next: run the common formatting layer against captured pipes and a pseudo-terminal, including
  UTF-8 bytes, long lines, EOF, interrupted I/O, color suppression and cleanup.
- Done when: The chosen second host passes common terminal encoding, color/capability, prompt, and raw-byte output tests, including redirected output and a terminal without color support.

### platform.portability.043 — Stack capture has no second-platform backend

- Next: provide address capture and current-image discovery for the chosen second platform behind
  the runtime host boundary.
- Related: platform.portability.003, platform.portability.045, platform.portability.044
- Done when: A stack captured on the chosen second host returns ordered addresses and their owning images for native and generated frames, with deterministic behavior when frames or images cannot be resolved.

### platform.portability.044 — Debug-symbol access has no second-platform backend

- Next: locate and read the target's debug information for captured addresses, leaving parsing and
  presentation in the existing common layer.
- Related: platform.portability.043
- Done when: The chosen second host resolves captured addresses from its debug information to function and source locations when symbols are present, and reports missing or stripped symbols without losing the raw addresses.

### platform.portability.045 — Debugger integration has no second-platform backend

- Next: implement debugger detection, break/attach behavior, and any debugger-facing host operations
  independently of stack-symbol presentation.
- Related: platform.portability.003, platform.portability.043
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

### platform.portability.053 — No second-platform text-input routing

- Next: translate committed native text input into the portable text event independently of IME
  composition.
- Related: platform.portability.049, platform.portability.052, platform.portability.061
- Done when: The chosen second-platform GUI emits committed Unicode text through the portable text event for ordinary, dead-key, and multi-codepoint input without confusing it with physical key events or IME composition.

### platform.portability.055 — No second-platform clipboard integration

- Next: implement clipboard ownership and platform-format conversion behind the portable typed-value
  contract.
- Related: platform.portability.050
- Done when: The chosen second-platform GUI reads and writes the supported typed clipboard values with clear ownership and format conversion, and round-trip tests cover text, empty data, and owner shutdown.

### platform.portability.057 — No second-platform GUI packaging

- Next: package the GUI runtime and native dependencies for the chosen second platform.
- Related: platform.portability.050, platform.portability.058, platform.portability.059
- Done when: A packaged GUI application on the chosen second platform launches on a clean target with its renderer, fonts, and native dependencies present, and a packaging smoke exercises open, render, and close.

### platform.portability.058 — No second-platform GUI font integration

- Next: connect GUI font selection and fallback to the installed-font catalog for the chosen
  platform.
- Related: platform.portability.016, platform.portability.057
- Done when: The chosen second-platform GUI selects installed faces and fallback families through the portable font catalog, and renders a mixed-script sample without relying on Windows font descriptors.

### platform.portability.059 — No second-platform file-dialog integration

- Next: connect the toolkit-owned file dialog to the target filesystem and native path expectations.
- Related: platform.portability.033, platform.portability.057
- Done when: The toolkit file dialog on the chosen second host opens and saves paths using native filesystem rules, reports cancellation and failure distinctly, and retains its common selection behavior in tests.

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
  Windows shared-policy checking reaches only the known log/logf cross-host foreign failures.
  Raw API HTML has no broken anchors/duplicate IDs; the existing __errno_location synthetic-name
  audit finding remains. These checks do not prove the reaper's JIT/unload or native lifetime.
- Next: add unload/late-destructor and descriptor-leak stress, exercise closed standard descriptors, continuous-output deadlines and descendant-held
  pipes, and run Windows process regressions. Do not mark lifecycle conformance from raw tests.
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
  Eight public file/directory/stream tests and two mapping cases pass in JIT/native. They cover
  opening modes, preservation on failed opens, inheritance flags, append seeks, directory rejection,
  concurrent handles, unlink-while-open, root links and owned mappings. Partial/interrupted I/O,
  permissions and broader common conformance still need dedicated execution.
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
- Next: exercise kernel-overflow stress, interrupted/partial I/O and permissions, run the remaining
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
- Priority contract: Linux supports Normal through SCHED_OTHER; other levels fail with ENOTSUP.
  Do not silently substitute real-time scheduling or process-wide nice changes. A broader mapping
  needs an explicit contract and permission/failure tests.
- Validation: 14 raw Linux tests pass in JIT/native, including gated C callbacks, distinct kernel
  identities, EBUSY from a live nonblocking join, scheduler validation and join result publication.
  Three public Core thread cases pass in JIT/native, covering reuse, priority-init failure cleanup,
  completion probes, wait-many and sleep/yield. Four common thread/timer cases also pass in
  JIT/native for context inheritance, one-shot and periodic behavior. Windows execution is unavailable.
- Next: exercise start failures, additional lifetime stress and the batching boundary,
  and decide whether to extend Linux priority support.
- Related: platform.portability.035
- Done when: The chosen second host passes common creation, join, yield, sleep, identity, and priority tests, including failed start and orderly shutdown, without duplicating lifecycle policy in its native leaf.

### platform.portability.036 — Validate the Linux calendar and monotonic clocks

- Evidence: Linux monotonic ticks use clock_gettime with nanosecond frequency. UTC/local calendar
  fields use reentrant glibc conversions, preserving milliseconds and historical zone offsets.
  Raw clock tests execute in JIT with UTC and native ELF with America/New_York, including negative
  epochs, leap days, summer/winter offsets and post-2038 dates. All 31 public DateTime, Timestamp,
  stopwatch and time cases pass in JIT/native in both UTC and America/New_York. Linux also
  supplies absolute-deadline sleep.
- Next: add a focused public local-calendar case spanning a DST transition; running the existing
  public suite under two zones does not establish that transition boundary.
- Related: platform.portability.037
- Done when: The chosen second host returns wall-clock fields and monotonic ticks in documented units; tests cover conversion, monotonic ordering, and elapsed time across scheduler sleeps.

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
- Related: platform.portability.036, platform.portability.029
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
- Next: finish environment mutation and desktop actions, with explicit unsupported outcomes.
- Related: platform.portability.005, platform.portability.010, platform.portability.015
- Done when: The chosen second host provides argument, environment-variable, locale, special-directory, and generic desktop-action operations through the portable API, with explicit unsupported results and focused contract tests.

### platform.portability.039 — Native errors have no second-platform mapping

- Next: map the second platform's error domain into the portable `core` failure contract, preserving
  native detail without leaking native codes into portable callers.
- Done when: Representative filesystem and process failures on the chosen second host map to portable core failures while retaining inspectable native detail, and common callers branch only on portable errors.

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
  JIT/native; native Windows validation is unavailable.
- Next: validate sandbox startup in separate processes before module/user code, then run the
  remaining common sandbox and filesystem conformance cases.
  The guards protect Core's operations; they are not an OS security boundary for arbitrary native
  calls and do not make path checks and subsequent mutations atomic against concurrent renames.
- Related: platform.portability.038, platform.portability.010
- Done when: The chosen second host applies sandbox restrictions before user code and imported native modules run, rejects forbidden filesystem and process actions in integration tests, and reports unsupported enforcement explicitly.

### platform.portability.001 — Neutral bin sources need a Linux build gate

- Evidence: DevMode and Release Linux compilers build from source. Lexer/parser and C++ suites
  pass; `--os linux` selects System V, hosted runtime bindings, ELF objects and GNU-linked native
  executables/archives. Static module consumers execute lifecycle hooks across imports. The
  default target is still Windows, and neutral standard/application modules have no Linux gate.
  Core's Linux filesystem, environment, thread, timer and sandbox leaves are implemented;
  watching, process launch and evdev gamepads are also implemented. Initial X11 desktop, mouse
  and keyboard leaves now unblock whole-Core linking and public test compilation.
  The `linux` ABI module independently tests descriptors, directories, ioctl, mappings, entropy,
  secure clearing, dynamic loading and clocks in JIT and native ELF. Core's public memory,
  filesystem, thread and initial desktop tests execute; other service suites are being validated.
- Next: complete the remaining Core host services and execute the public resource-owner suites.
  Validate gamepad state/vibration and discovery on an input-enabled host. Select headless/no-sound backends only where
  their contracts permit them; do not treat absent declarations or success stubs as a backend.
- Done when: a Linux configuration compiles every neutral runtime and bin source and fails on
  an accidental native Windows import.

### platform.portability.005 — Validate argument lifetime across native Unix modules

- Evidence: ELF startup passes argc/argv into `ProcessInfo.arguments` before runtime setup.
  Native executable probes preserve empty values, spaces, quotes, trailing backslashes, tabs
  and UTF-8. Shared-module consumers compare the full argument vector with their provider,
  including after relocating a published executable/library pair. Core's command-line string
  fallback now lives entirely in the Windows leaf; Linux retains the runtime's original argv.
- Next: validate argument lifetime through dynamic module unload. Retain the Windows
  command-line path.
- Related: platform.portability.003, platform.portability.008, platform.portability.010
- Done when: shared Unix modules observe the original argument order and bytes through
  initialization, calls and cleanup without reading storage owned by an unloaded module.

### platform.portability.008 — Validate the argv-first process API

- Progress: StartInfo.arguments is now a borrowed nullable slice of strings; null/empty means
  no arguments after argv[0]. startProcess/runProcess accept separate argument values, and
  Windows serializes them with the existing C-runtime quoting algorithm. Programs with their own
  grammar, including cmd.exe tests, explicitly use the Windows-only nativeArguments escape hatch.
  The common entry validates zero bytes, empty required names, environment names and conflicting
  argument forms before calling the host leaf. Linux explicitly rejects nativeArguments.
- Migration: Prism build/format/preview workers, Scope thumbnails, Pixel child tests, Vault's
  visibility probe and debugger launch now pass vectors without manual quoting. This is a source
  API change: callers passing a command-line string must pass a vector or explicitly choose
  StartInfo.nativeArguments for Windows. No shell is inserted implicitly.
- Validation: raw Linux spawn probes preserve exact argv in JIT/native and an imported consumer.
  Whole-Core test/doc compilation succeeds. Windows semantic/test compilation on this Linux host
  stops at the known foreign log/logf imports.
  The public argument-validation tests, native Windows quoting path and application consumers
  still need execution with a complete Core backend; formatting is not their runtime validation.
- Next: execute public Linux child roundtrips and focused
  Prism/Scope/Pixel/Vault consumers on supported hosts.
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
  a Windows descriptor.
- Next: replace it with family/subfamily names, normalized style properties, file path, and face
  index. The platform hook should enumerate font files or configured font directories, not
  manufacture a native font handle.
- Done when: The public installed-font descriptor contains normalized family, subfamily, style, path, and face index without LOGFONTW or native handles, while Windows enumeration still loads and selects the same installed faces.

### platform.portability.017 — Connect installed-font sources to the common scanner

- Next: feed host-discovered files into `Pixel.FontCatalog.addFile` and replace installed-family
  callers of the native descriptors with the resulting `FontFileFace` file/index metadata.
  The common catalog can already parse collections and load a selected face without GDI.
- Related: platform.portability.016, platform.portability.019, platform.portability.020, platform.portability.018
- Done when: Common Swag code scans font files and collections with the existing TrueType/OpenType reader into portable face descriptors, and a host-supplied file list produces the same catalog independently of enumeration backend.

### platform.portability.018 — Finish installed-family grouping and cache integration

- Next: integrate `FontCatalog`'s deterministic family/style selection with installed-font caching
  and replace the Windows grouping callbacks. Add typographic family/subfamily names and legacy
  aliases so separately named light and semibold faces can join their intended family.
- Related: platform.portability.016, platform.portability.017
- Done when: One common catalog groups scanned faces by family, selects regular/bold/italic fallbacks, and sorts and caches results identically for equivalent Windows and synthetic second-host font lists.

### platform.portability.020 — Linux has no installed-font source

- Next: a first Linux backend may provide conventional directories. Fontconfig can be added later
  for aliases, user configuration and substitutions without making basic parsing and grouping depend
  on it.
- Related: platform.portability.017
- Done when: A Linux backend discovers installed fonts from documented system and user directories and feeds the common scanner, with tests for collections, missing directories, duplicates, and readable fallback families.

### platform.portability.006 — `Crypto.secureClear` has no portable no-elide primitive

- Evidence: `crypto/security.win32.swg` calls the foreign `RtlZeroMemory` routine. The Linux
  leaf uses glibc explicit_bzero; raw tests verify zeroed bytes and surrounding canaries in
  JIT and native ELF. Five public crypto cases pass JIT/native, including empty buffers,
  getentropy chunk boundaries, canaries and clearing.
- Next: inspect optimized secureClear calls to establish the no-elide guarantee end to end.
- Related: platform.portability.075
- Done when: Crypto.secureClear is available on Windows and the chosen second target, clears every requested byte, and optimized-code inspection or an equivalent no-elide check proves the wipe survives optimization.

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

- Evidence: `core/src/tests/filesystem/path.test.swg` already tests lexical Windows path behavior
  without touching the filesystem.
- Next: extend that coverage to independent target-policy tables for Windows and Unix: root forms,
  case policy, trailing separators, dot segments, invalid names, and normalization. A host must be
  able to exercise both policies without running another OS.
- Related: platform.portability.012
- Done when: One test run on either host exercises Windows and Unix lexical policy tables for root, case, separators, dot segments, invalid names, and normalization, without filesystem access or host-dependent expectations.

### platform.portability.054 — Native input has no portable mouse, touch, and pen adapter

- Evidence: the current Windows backend polls mouse state but does not translate `WM_POINTER`,
  `WM_TOUCH`, or `WM_GESTURE` into contacts.
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
- Related: platform.portability.050, platform.portability.084, platform.portability.052, platform.portability.055, platform.portability.056
- Done when: The chosen second-platform surface enumerates active monitors, uses the correct per-monitor scale during open, move, and resize, and updates placement after topology or scale changes without exposing native monitor handles.

### platform.portability.052 — No second-platform keyboard routing

- Progress (Linux): Core polls X11 keymaps and keyboard mappings, exposes canonical keysyms as
  VirtualKey values, maps common modifiers and the first three mouse buttons, and snapshots basic
  Latin-1/Unicode characters with Shift/Caps Lock in the first group. Pointer query/warp is also
  implemented. Xvfb and no-display checks pass JIT/native. Extra buttons, additional groups,
  dead keys/compose, IME, layout-change routing and synthetic key-transition tests remain pending;
  polling snapshots are separate native requests, not one atomic input sample.
- Next: translate native key identity, modifier, repeat, and layout state into the portable keyboard
  events.
- Related: platform.portability.050, platform.portability.085, platform.portability.053, platform.portability.054
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
- Named scope remains Windows-only: Prism's interprocess event must retain shared-name scope,
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

### platform.portability.078 — No Linux FUSE backend

- Owner: Swag Vault
- The existing boundary includes system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, the WinFsp layer and mount-point selector, and `autounmount.win32.swg` for session
  lock, suspend, and idle monitoring. The container format, logical filesystem, password widget,
  and auto-unmount decisions live above those native mechanisms. The Linux mount backend remains
  this entry's outcome; native session and idle monitoring must also be accounted for before the
  full application port ships.
- Next: map the logical filesystem to the chosen FUSE interface, specifying mount ownership,
  permission translation, cancellation, and callback shutdown before packaging the backend.
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
  resize/show/close requests, UTF-8 titles and window-manager hints, bounded event dispatch,
  close-request versus destruction semantics and offscreen realization are implemented. Two
  public cases pass JIT/native under Xvfb, covering moved owners, resize callbacks, monitor/pointer
  queries, WM_DELETE_WINDOW, repeated close, external destruction and closing from a paint callback. A separate opt-in
  case validates neutral queries and failed creation without a display. Explicit paint events
  also work for fully offscreen windows, where ClearArea would produce no Expose event.
  The lazy connection retains optional RandR and XFixes libraries until disconnect, avoiding extension-cache
  identities accumulating from repeated unload/reload. Window operations stay on the creating
  thread; module shutdown invalidates owners before releasing native state. Connection-loss,
  module-unload stress and window-manager integration still need dedicated execution.
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
  retirement. All 92 Pixel golden tests pass natively without changing references. The full golden-only
  campaign reaches GUI and all four applications, but they stop before execution at missing Linux GUI
  services (application/surface/cursor types, clipboard, installed fonts and user locale).
  Native artifact work remains in .093.
  Core still has no mandatory GL/EGL dependency. GUI integration and physical GPU validation
  remain open, as do GUI surfaces, cursor shapes and native Wayland.
- Evidence: the filenames already expose most of the seam: `surface.win32.swg`,
  `application.win32.swg`, `clipboard.win32.swg`, `dragdrop.win32.swg` and `cursor.win32.swg`, with
  shared Windows clipboard text conversion in `nativetext.win32.swg`. The retained tree, layouts,
  themes, controls and the toolkit-owned file dialog are platform-neutral. These leaves identify
  mechanisms to replace; their file count is not a porting plan.
- Next: build the GUI application/surface and renderer adapters on the Core X11 owner, finish
  cursor shapes and input routing, and run a rendered application with a window manager.
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
  same descriptor accepts platform.portability.020's source.
- Related: platform.portability.016, platform.portability.019, platform.portability.020

### platform.portability.019 — A system face cannot load directly from file and face index

- Evidence: `TypeFace.createAt(fullName, bytes, faceIndex)` and
  `TypeFace.loadAt(fullName, faceIndex)` now select a zero-based collection face. Existing
  `create`/`load` select index zero. Cache keys include both name and index; native and JIT
  regressions cover distinct styles, repeated lookups, invalid indices, and copied-byte lifetime.
  Installed-family selection still uses `createFromHfont`; it does not yet supply a portable
  descriptor to these APIs.
- Next: connect a portable installed-font descriptor's file and face index to `TypeFace`
  creation, keeping `createFromHfont` as an optional Windows adapter.
- Done when: a system-family selection loads the requested collection face from its
  descriptor without manufacturing a GDI font handle.
- Related: platform.portability.067, platform.portability.016, platform.portability.017

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
- Related: platform.portability.036

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
- Related: platform.portability.004, platform.portability.005

### platform.portability.010 — Early argument lookup retains a Windows command-line fallback

- Evidence: Core's premain command-line string fallback is confined to environment.win32.swg.
  Name/value matching now lives in `findRunArgumentIn`, shared by both backends. Linux uses argv
  directly because ELF startup publishes it before module initialization. Windows still searches
  `Swag.args()` first, then parses `GetCommandLineA` when native early startup needs the fallback.
- Next: validate Linux sandbox startup with complete Core, make Windows argv available before
  native module initialization, and remove that platform's early command-line fallback.
- Done when: native and compile-time early argument lookup use the same populated vector
  and preserve sandbox, smoke, and corpus argument behavior.
- Related: platform.portability.005, platform.portability.008

### platform.portability.014 — The Windows virtual-key alias remains in portable input declarations


- Evidence: image handle conversions and `Surface.win32Handle` already live in Windows
  adapter files. Their native signatures are intentional optional interoperability.
  `Input.VirtualKey`, however, is still declared in neutral `key.swg` and exercised in
  neutral `key.test.swg`; the conversion functions themselves live in `keyboard.win32.swg`.
- Next: keep that alias and its tests with the optional keyboard adapter. Common declarations
  and consumers should need only `Input.Key` and normalized events.
- Done when: a neutral input compilation contains no virtual-key declaration or native
  adapter dependency, while Windows keyboard conversion tests still cover the mapping.

### platform.portability.065 — Audio has no real non-Windows backend

- `DriverKind` is `Default`, `NoSound`, `XAudio2`. Off Windows, `Default` resolves to silence.
- The backend dispatcher already supports explicit `NoSound`, uses it as the non-Windows
  default, and rejects unavailable `XAudio2`. Its repeated compile-time branches still need the
  interface work in platform.portability.027 before another backend is added. CoreAudio and ALSA or PulseAudio are the obvious
  targets; WASAPI directly would also remove the XAudio2 dependency on Windows.
- Next: once platform.portability.027's backend interface exists, implement one non-Windows
  output backend (CoreAudio, or ALSA/PulseAudio) behind it.
- Done when: one chosen non-Windows target opens a real output device and passes the common
  engine, voice, bus, streaming, and device-lifecycle contract while `NoSound` remains explicit.
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
- Evidence: the Windows leaf implements blocking IPv4 TCP. There is no POSIX leaf, IPv6,
  datagram transport or resolver backend yet.
- Next: extend the address and ownership contracts and implement the missing host leaves for
  blocking TCP, UDP, and host/service resolution. Keep native handles and error translation
  inside those leaves; add readiness only after the common concurrency contract is decided.
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
- Next: choose the first non-Windows target and implement its screen/window/region capture beside
  `screenshot.win32.swg`.
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

### platform.portability.074 — File-type registration is Windows-only

- Intent: `Env.registerApplication`, `Env.associateFileExtension`, and the shell integration entries
  above are the whole platform boundary; the viewers, streaming, and structure readers are portable.
- Next: once platform.portability.015 settles the application-integration contract, move
  Swag Scope's `--register-file-types` path onto it.
- Done when: desktop registration goes through whatever portable contract platform.portability.015 settles on.
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

- Evidence: complete DevMode and Release Linux compilers pass lexer/parser suites and focused
  compile-time/native probes. The full C++ campaign passes all 1,743 tests, including the original
  PE resource failure and added native/shared-module regressions. Cross-target JIT execution
  uses host context, TLS and process storage; native output keeps its target instructions.
  DWARF frame registration preserves C++ cleanup through generated faults, and native ELF/JIT
  tests recover protected-page faults and stack exhaustion. Compiler-owned pthread callbacks
  now retire before their code is unmapped, including active callbacks which delete their key.
  Linux directory locks still do not prohibit an uncoordinated cleaner's rename.
- Next: coordinate directory cleanup with API readers/publication. Extend fault-boundary
  coverage across native callbacks and nested JIT calls while preserving C++ cleanup.
- Done when: concurrent cleanup cannot invalidate an active reader/publication generation,
  and nested JIT/native fault recovery preserves ownership without stale code or storage.
- Related: platform.portability.001, platform.portability.092, platform.portability.093

### platform.portability.092 — System V aggregate lowering and target activation are missing

- Evidence: the internal System V profile implements six integer/eight vector argument registers,
  independent banks, callee-save rules, zero shadow space and variadic AL setup with explicit
  liveness. Source-level C ellipses now pass individual ABI arguments with default numeric
  promotions, including indirect calls and simultaneous integer/vector bank overflow. The
  focused variadic source suite passes 106 tests in JIT and native ELF. Native C fixtures exercise mixed scalar banks, stack arguments, variadic floats and
  indirect calls after physical-register DCE. Source attributes select the concrete profile
  through C, resolved per compiler instance rather than the process-wide default. Windows remains the
  default target while the Linux runtime is incomplete. The storage classifier and argument planner cover
  mixed/nested records, unions, SIMD upper halves, unaligned fields and whole-argument bank
  rollback. The packed-address call bridge now passes mixed/two-register/stack aggregates,
  handles hidden memory results and variadic aggregate banks, and bounds partial eightbyte
  reads/writes against guard pages. Prepared aggregate calls also preserve physical/virtual
  sources before assigning mixed ABI lanes, including hidden memory results. Generated callees
  receive register and stack aggregates without overwriting other incoming lanes, fill hidden
  memory results and return mixed/two-register/partial/SIMD storage to native callers; liveness and machine-code
  cache identity retain additional result registers. Runtime interface adapters translate Swag
  arguments to the concrete host ABI and preserve its wider clobber set in the Swag frame.
  Semantic type normalization now distinguishes by-value stack arguments from hidden-pointer
  results and keeps prepared aggregate type handles stable through lowering. Source parameter
  layout now uses the whole-argument planner, reserves hidden-pointer lanes and homes split
  register/stack values before scalar captures. Native codegen fixtures cover those homes at
  O0 and O2, including strings and later scalar lanes. Call expressions reserve caller-owned
  result storage for split register returns and retain temporary ownership without adding
  hidden arguments. Callees capture split results before cleanup, and ordinary AST function
  visitors round-trip mixed/two-register/string/memory values at O0 and O2. Final emission uses
  the function ABI, retains every result lane and fingerprints aggregate register classes.
  A parsed deferred body can replace the source and publish a side effect while the captured
  result stays intact at O0 and O2. Typed JIT invokers consume the host frame ABI and classify
  register/stack arguments, hidden results and variadic vector counts; their cache stores full
  aggregate shapes independently of semantic types and per-call addresses. Runtime setup/hooks
  and one-argument evaluation entries use their Swag scalar ABI on the Linux host; the explicit
  invocation boundary prevents GCC 14 from merging incompatible ABI calls. A native fixture
  also checks that a Swag post-copy hook updates both System V result lanes without dropping
  the borrowed argument at O0 and O2. Owned-local and temporary cleanup, end-to-end source
  execution and over-aligned stack values still need validation or integration.
- Next: validate owned-local and temporary return cleanup and complete end-to-end source execution; add
  dynamic alignment for over-aligned stack values.
  Compare with native C/C++ fixtures and complete Linux runtime lifecycle and signal support.
- Done when: generated Linux calls round-trip supported scalar and aggregate values through C,
  preserve callee-save registers and stack alignment, and use the same ABI in JIT and native code.
- Related: platform.portability.001, platform.portability.081

### platform.portability.093 — Linux native output needs module, PIC and debug integration

- Evidence: `ELFObjectWriter` emits ELF64 relocatable code/data/BSS with explicit RELA
  addends, undefined symbols and exported aliases. A GNU linker consumer executes these
  objects and verifies external calls, shared data and unwinding through generated code.
  Prepared images share native code/data lowering; Linux unwind output uses relocatable
  DWARF CIE/FDE records. The native object factory supports ELF partitions, and a GNU
  archive consumer verifies writable-global pointers into separately extracted constants.
  The Linux linker publishes GNU-linked ELF executables and deterministic GNU archives; its System V
  main entry installs argc/argv before runtime initialization. Native startup, argument-byte
  preservation, runtime synchronization, panic cleanup and deterministic parallel outputs pass.
  Static module dependencies resolve their actual published filenames, including custom names;
  executable consumers verify initialization, pre-main and cleanup for static and shared imports.
  Shared providers observe their consumer's context and exact argument vector. Child launch paths
  use LD_LIBRARY_PATH without changing the compiler environment. Published .so dependencies
  survive relocation, and disabling publication removes the old copies. Shared imports also
  execute from `#run`: lookup accepts both Swag module.so and conventional libmodule.so names,
  with context/argument sharing verified by DevMode and Release compilers.
  Nested shared dependencies are preloaded from the resolved graph for JIT calls; GNU ld receives
  link-only search paths for their DT_NEEDED entries. A three-module consumer executes compile-time
  and native calls with DevMode and Release compilers without publishing dependencies beside it.
  API publication reconstructs resolved foreign module, symbol, link and ABI attributes, including
  declarations inside attribute blocks and a directly annotated function inheriting its ABI.
  Export and static-library consumers call libc/libm through these declarations in JIT and native
  ELF; a real Linux-binding consumer also exercises read, errno and strerror across the import.
  Source debug output is explicitly rejected until DWARF source records exist. Shared-library
  linking currently permits text relocations; it does not establish PIC or loader lifecycle support.
  Persistent native function caches remain COFF-specific and are disabled for Linux.
  Companion archives retain only module-specific runtime hooks; the generic lookup alias is
  created when linking the shared object. Static transitive consumers pass with DevMode and
  Release compilers, and a Core/Ogl archive consumer renders and reads pixels in JIT/native.
  GNU tool response files use short paths relative to their working directory. On Pixel's
  30,124-member archive, controlled rebuilding with the same ar options took 68 seconds with
  long absolute operands versus 16 seconds with short operands; both 40 MB archives were byte-identical.
  The compiler's 1,750 C++ tests pass with relative operands, including native/shared linking,
  companion archives, deterministic artifacts and transitive initialization.
  Public ELF names include a lossless artifact identity, also emitted into generated Foreign
  attributes. Two modules exporting `value` now retain distinct calls in shared and static
  compositions; DevMode/Release consumers, the full C++ suite and a native Ogl importer pass.
  Existing Linux libraries and their generated APIs must be rebuilt together for this ABI change.
- Next: validate dynamic load/unload
  lifecycle, and finish PIC relocations, source-level
  DWARF and target-specific incremental caches. Preserve the working native executable and archive consumers.
- Done when: Linux executables and shared libraries link and run a runtime/native workspace smoke,
  including foreign imports, arguments and cross-module initialization/cleanup.
- Related: platform.portability.005, platform.portability.092
