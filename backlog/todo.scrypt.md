# sCrypt Roadmap

This file is the product roadmap for sCrypt: what the application must gain to stand next to a
mature disk-encryption tool. It is scoped to this module and to the `bin/std` primitives sCrypt
depends on.

It is not the repository's discovery backlog. Platform leads and defects belong in the `findings.*`
files — [findings.gui.md](findings.gui.md) for the surface,
[findings.optimization.md](findings.optimization.md) for the crypto throughput; compiler and
language intent belongs in [todo.compiler.md](todo.compiler.md) and
[todo.language.md](todo.language.md). Keep them separate: this file holds intent about the product,
the `findings.*` files hold evidence about the platform. [README.md](README.md) has the whole
layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Several entries are owned by `bin/std` rather than by sCrypt. Locked key memory is a
standard-library primitive that happens to have been discovered here; it must not be reimplemented
locally.

---

## Tier A — Throughput and credibility

### T-087 — No block cache

- Owner: sCrypt
- Problem: `Volume.readPhysical` reads 4124 bytes, decrypts, and verifies the tag on every single
  call, with no memory between calls. An unaligned write costs a read, a decrypt, an encrypt and a
  write. A sequential 1 MiB read is 256 separate 4 KiB I/O operations that are never coalesced.
- Fix: a bounded LRU cache of decrypted blocks, held in locked memory and wiped at unmount.
- Related: a bounded cache is also the natural place to put an explicit memory budget, which any
  later working-set investigation will need. See T-248 and T-249 for the independent throughput
  work around it.

### T-248 — Physical block I/O is never coalesced

- Owner: sCrypt
- Coalesce physically contiguous encrypted blocks into bounded reads and writes without requiring
  them to be resident in T-087's cache.
- Related: T-087, T-249

### T-249 — Block decryption is not batched

- Owner: sCrypt
- Decrypt independent blocks in bounded `Jobs` batches while preserving request ordering and
  cancellation.
- Related: T-087, T-248, T-260

### T-088 — ChaCha20 processes one block per dependency chain

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Problem: `chacha20.swg`, although its rounds auto-vectorize, remains one block wide and bounded
  by its dependency chain and memory traffic.
- Evidence: ChaCha20's packed state remains one block-wide and its dependency chain still limits
  throughput; the current measurements and protocol are in
  [F-029](findings.optimization.md#f-029--chacha20-still-processes-one-block-per-packed-dependency-chain).
- Fix: process several blocks per loop iteration, which is where the remaining ChaCha SIMD win is.
- Why it matters: the mount latency a user actually feels is almost entirely this, and every
  block read and written pays the key-stream rate.
- Related: T-250, T-251, T-252

### T-250 — Poly1305 remains scalar

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Optimize Poly1305 independently of ChaCha20 and retain differential vectors for every block-tail
  length.
- Related: T-088

### T-251 — The Argon2 permutation remains scalar

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Vectorize the Argon2 compression/permutation with profile benchmarks and unchanged published
  vectors.
- Related: T-252

### T-252 — Independent Argon2 lanes run serially

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Run lanes within each legal slice through `Jobs`, respecting Argon2's synchronization points and
  measuring the configured `parallelism` contract.
- Related: T-251

### T-089 — Keys live in pageable memory

- Owner: `bin/std` for the locked allocation, sCrypt for the policy
- Problem: `Crypto.Keys` and the unwrapped master key are ordinary memory. The page file or a crash
  minidump can capture the master key. VeraCrypt locks its key pages.
- Fix: provide a locked-memory allocation in `bin/std` and require sCrypt's unwrapped keys to use
  it. Keep dump exclusion and lifecycle wiping independently testable.
- Related: T-253, T-254, T-255

### T-253 — Key pages are not excluded from Windows crash dumps

- Owner: sCrypt
- Register key regions for exclusion from Windows Error Reporting dumps and verify the configured
  dump policy.
- Related: T-089

### T-254 — Session lock does not wipe mounted keys

- Owner: sCrypt
- On workstation/session lock, unmount or wipe every live key according to an explicit failure
  policy.
- Related: T-089, T-256

### T-255 — System suspend does not wipe mounted keys

- Owner: sCrypt
- Handle suspend independently of session lock and wipe or unmount before sleep completes.
- Related: T-089, T-257

### T-090 — The executable is not signed

- Owner: release process
- Problem: the application requests UAC elevation to start the driver. Unsigned, the consent dialog
  reads "Unknown publisher" for an encryption tool. This is a larger adoption obstacle than any
  feature on this list.
- Fix: an OV or EV code-signing certificate, applied to `sCrypt.exe`.
- Note: elevation is only required because the portable WinFsp driver has to be registered by the
  guardian process. A system-wide WinFsp installation makes `loadWinFsp` take the installed runtime
  and skip the guardian entirely, which is also what allows an automated end-to-end test loop
  without a consent dialog on every run.

---

## Tier B — Perceived feature parity

### T-091 — A busy volume cannot be forcibly unmounted

- Owner: sCrypt
- Add an explicit forced-unmount flow when an open handle keeps a volume busy, including user
  confirmation, outstanding-I/O cancellation, and a truthful result.
- Note: the startup list is persisted with `needsPassword` beside each path, which is what keeps a
  start quiet for an unprotected vault. It is not a hint an attacker could not obtain in one Argon2
  attempt, but it does mean the state file says which vaults have no password.
- Related: T-256, T-257, T-258

### T-256 — No automatic unmount on session lock

- Owner: sCrypt
- Unmount protected volumes on session lock, independently of key-memory wiping.
- Related: T-091, T-254

### T-257 — No automatic unmount on system suspend

- Owner: sCrypt
- Unmount protected volumes on suspend with a defined response when a volume is busy.
- Related: T-091, T-255

### T-258 — No automatic unmount after idle

- Owner: sCrypt
- Add an opt-in idle timeout based on appropriate user activity and reset semantics.
- Related: T-091

### T-092 — Additional password slots are not in the interface

- Owner: sCrypt
- Problem: `Volume.addPassword` and `Volume.removePassword` still have no way in. A container can
  hold four passwords and the interface only ever writes the one a reader opened it with.
- Fix: a key-slot list that can add and revoke passwords and show how many slots are occupied
  without claiming which password maps to which slot.
- Note: `KeySlotCount` is 4. Raising it costs one constant and a wider `keySlotMask`, but it also
  multiplies the cost of rejecting a wrong password; see T-088.
- Related: T-259

### T-259 — No key-derivation cost-profile selector

- Owner: sCrypt
- Expose `Crypto.Argon2Profile` independently of password-slot management, with clear latency and
  memory guidance.
- Related: T-092, T-251, T-252

### T-093 — Shrinking a container

- Owner: sCrypt
- Problem: capacity can only go up.
- Fix: evacuating every block above the new limit, then truncating. More work than growing, and far
  less value — a container that has to be rewritten to lose space is a poor trade. Ranked here
  because it is the other half of a capacity a reader can change, not because it is urgent.

### T-094 — Header backup and restore

- Owner: sCrypt
- Problem: the key slots and both header slots live in the same file, in its first megabytes. One
  bad sector there destroys the whole container, including data blocks that are perfectly intact.
- Fix: export and restore of an independent encrypted header file, exposed in the interface. The
  export must cover the key slot area as well, because that is now where the master key lives.
- Document the trap VeraCrypt also documents: restoring a backed-up header reinstates the passwords
  that were current when the backup was taken.

### T-095 — Keyfiles

- Owner: sCrypt
- Key slots exist, so this is now only mixing: the slot key derives from the password combined with
  a hash of the keyfiles, under a deterministic ordering. `Core.Crypto.argon2id` already accepts a
  secret and an associated-data input for exactly this. PKCS#11 tokens are a further step and can
  wait.

### T-097 — Filesystem callbacks use one coarse lock

- Owner: sCrypt
- Problem: WinFsp runs under the coarse guard strategy, so every callback is serialized and all
  encryption for a large copy sits on one thread.
- Fix: replace the coarse guard with per-node locks plus a metadata lock.
- Sequencing: after T-087, and only alongside a concurrent stress test. Getting this wrong is a
  correctness failure, not a performance regression.
- Related: T-260

### T-260 — Large sCrypt operations do not parallelize block encryption

- Owner: sCrypt
- Parallelize independent block encryption through bounded `Jobs` batches after the locking model
  is safe, with cancellation and deterministic error propagation.
- Related: T-097, T-249

---

## Tier C — Long term

### T-098 — Hidden volume

- Owner: sCrypt
- The format already permits it: the container is entirely random, carries no magic, and derives
  its record locators from the key (`Crypto.recordLocator`). A second key slot area and header at a
  key-derived offset hide naturally.
- The real work is not the format. It is the protect-hidden-volume mode, where the outer volume
  must refuse writes into the hidden region without ever revealing that the region exists, and the
  interface for that constraint.
- Sequencing: last. A hidden volume that leaks is worse than no hidden volume, because it promises
  a protection it does not deliver.

### T-099 — No normative container-format specification

- Owner: sCrypt
- Write a normative format document independent of the implementation, covering layout, key
  derivation, record framing, validation order, versioning, and failure indistinguishability.
- Related: T-261, T-262, T-263, T-264, T-101

### T-261 — No published sCrypt format test vectors

- Owner: sCrypt
- Publish deterministic vectors for key derivation, headers, records, locators, and full minimal
  containers so independent implementations can be compared.
- Related: T-099, T-101

### T-262 — Attacker-controlled container decoders are not fuzzed

- Owner: sCrypt
- Fuzz `Volume.restore`, `Volume.loadNodes`, `Node.deserialize`, and `JournalRecord.decode` with
  reproducible corpora and sanitizer coverage.
- Related: T-099, T-101

### T-263 — Crash tests do not cover torn records or checkpoint kills

- Owner: sCrypt
- Extend crash consistency beyond between-operation snapshots to torn writes inside a record and
  process termination during checkpointing.
- Related: T-099

### T-264 — Metadata scaling stops at 1,200 files

- Owner: sCrypt
- Add a bounded performance and correctness test at one hundred thousand files.
- Related: T-087, T-099

### T-100 — No Linux FUSE backend

- Owner: sCrypt
- The boundary is already where it needs to be: system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, plus the WinFsp layer and the mount-point selector. Everything above them — the
  container format, the logical filesystem, the password widget — is platform-independent already.
  Real work, no design risk.
- Related: T-265, T-307

### T-265 — No macOS filesystem backend

- Owner: sCrypt
- Add the macOS mount backend and packaging independently of Linux, choosing the supported FUSE or
  native filesystem mechanism explicitly.
- Related: T-100, T-307

### T-101 — External audit

- Owner: project
- After T-099. Until it happens, the format and the implementation have had no independent
  cryptographic review, and sCrypt is not a proven replacement for VeraCrypt on critical data — no
  matter what else on this list ships.

---

## Out of scope

**Partition and system-disk encryption.** WinFsp is a filesystem proxy, not a volume driver.
Supporting this means writing a kernel-mode virtual disk driver and a pre-boot authenticator: a
different product, and one that destroys the portable, no-installation property that is currently
sCrypt's genuine advantage. This is a case where a mature block-level tool is simply the right
answer, and sCrypt should say so rather than chase it.

**Cipher cascades and a user-facing cipher menu.** Format agility yes; a dropdown no. Cascades are
theatre; they triple the bug surface for no defensible gain over a correctly implemented modern
AEAD. The format carries a version, so changing algorithm later stays possible without exposing the
choice.

**Reading a container older than format version 3.** Version 3 replaced the key schedule, the KDF
and the record framing at once, so nothing an earlier version wrote can be read without a parallel
implementation of all three. The container also reports the same outcome for a wrong password, a
damaged container and an older format, deliberately: telling them apart is exactly what the design
refuses to do.
