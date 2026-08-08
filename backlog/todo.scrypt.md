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
- Fix: a bounded LRU cache of decrypted blocks, held in locked memory and wiped at unmount;
  coalescing of physically contiguous blocks into single I/O operations; and batched block
  decryption parallelized with `Jobs`. This is where the five-to-tenfold throughput factor is.
- Related: a bounded cache is also the natural place to put an explicit memory budget, which any
  later working-set investigation will need.

### T-088 — The crypto primitives are scalar

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Problem: `poly1305.swg` and `argon2.swg` are straightforward scalar implementations, and
  `chacha20.swg`, although its rounds now auto-vectorize, is still bounded by memory traffic.
  Argon2id measures 403 ms at the Interactive profile and 2 396 ms at the Moderate default
  (release build, m=256 MiB, t=3, p=4), and rejecting a wrong password costs that four times
  over, because every key slot is probed whether or not it holds a password.
- Done so far: the backend's SSE2 auto-vectorizer (release builds, `cpuVectorize`) compiles the
  ChaCha20 double-round loop to packed code (~90 instructions instead of ~500 scalar ones), the
  key-stream application and 32-bit marshalling work a word at a time instead of a byte at a time,
  and the packed state now stays register-resident across the ten rounds instead of round-tripping
  through the frame — end-to-end `chacha20Xor` +21%, with the numbers and the measurement protocol
  in [F-029](findings.optimization.md#f-029--chacha20-throughput-is-bounded-by-memory-round-trips-not-by-round-arithmetic).
- Fix: process several blocks per loop iteration, which is where the rest of the ChaCha SIMD win
  is (F-029 again), then revisit `poly1305` and the Argon2 permutation. Argon2's lanes are also
  independent within a slice, so `Jobs` can run `parallelism` of them at once.
- Why it matters: the mount latency a user actually feels is almost entirely this, and every
  block read and written pays the key-stream rate.

### T-089 — Keys live in pageable memory

- Owner: `bin/std` for the locked allocation, sCrypt for the policy
- Problem: `Crypto.Keys` and the unwrapped master key are ordinary memory. The page file or a crash
  minidump can capture the master key. VeraCrypt locks its key pages.
- Fix: `VirtualLock` on key pages, exclusion from Windows Error Reporting dumps, and key wipe on
  session lock and on system suspend. Small surface, large credibility return.

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

### T-091 — Mount comfort and mount-time safety

- Owner: sCrypt
- Shipped: several volumes at once, each on its own letter, listed in the third card of the window;
  a per-vault mark that mounts it again at the next start, with one password prompt per protected
  vault; containers that open without a password at all; and a read-only mount, which opens the
  file without write access at all, declares `ReadOnlyVolume` to WinFsp, and refuses every change
  in the volume layer with `ErrorKind.WriteProtected`.
- Missing: forced unmount when a handle keeps a volume busy, and automatic unmount on session lock,
  on suspend, and on idle — both are a security feature rather than a convenience, and they are
  what remains of the *perceived* gap against VeraCrypt.
- Note: the startup list is persisted with `needsPassword` beside each path, which is what keeps a
  start quiet for an unprotected vault. It is not a hint an attacker could not obtain in one Argon2
  attempt, but it does mean the state file says which vaults have no password.

### T-092 — Additional passwords are not in the interface

- Owner: sCrypt
- Shipped: changing the password of a container, and removing it by leaving the new one empty,
  through the `Password…` action of the open-vault card.
- Problem: `Volume.addPassword` and `Volume.removePassword` still have no way in. A container can
  hold four passwords and the interface only ever writes the one a reader opened it with.
- Fix: a key-slot list on that dialog — add a password, revoke one — plus a cost-profile selector
  backed by `Crypto.Argon2Profile`. Both need a way to show how many slots are in use without
  claiming which of them is which.
- Note: `KeySlotCount` is 4. Raising it costs one constant and a wider `keySlotMask`, but it also
  multiplies the cost of rejecting a wrong password; see T-088.

### T-093 — Shrinking a container

- Owner: sCrypt
- Shipped: growing, through `Volume.grow` and the `Capacity…` action. The file is extended, the
  added region is randomized like a fresh container, and only then does a checkpoint publish the
  new geometry, so an interruption leaves the container exactly as it was.
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

### T-096 — Randomized block allocation

- Owner: sCrypt
- Problem: `BlockAllocator.allocate` always returns the lowest free block. An adversary comparing
  two snapshots of a container learns exactly which blocks changed and in what order, and therefore
  the sizes and sequence of writes.
- Fix: pick randomly within the free list. A few lines, and it blurs the signal considerably.
- Note: this now also applies to metadata pages, which are allocated the same way at every
  checkpoint.

### T-097 — Concurrency

- Owner: sCrypt
- Problem: WinFsp runs under the coarse guard strategy, so every callback is serialized and all
  encryption for a large copy sits on one thread.
- Fix: finer granularity — a per-node lock plus a metadata lock — and block encryption parallelized
  through `Jobs`.
- Sequencing: after T-087, and only alongside a concurrent stress test. Getting this wrong is a
  correctness failure, not a performance regression.

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

### T-099 — Format specification, test vectors, fuzzing

- Owner: sCrypt
- An audit is not possible without a normative format document that is independent of the code,
  plus published test vectors. Then:
  - Fuzz `Volume.restore`, `Volume.loadNodes`, `Node.deserialize` and `JournalRecord.decode`. Their
    comments record that the plaintext is attacker-controlled once the password is known, so a
    maliciously crafted shared container is a real attack surface.
  - Extend the crash-consistency tests. The current ones copy the container between operations and
    replay it; what is still missing is a torn write *inside* a record and a kill during a
    checkpoint rather than between them.
  - Add a scaling test at a hundred thousand files. The metadata paging test stops at 1 200.

### T-100 — FUSE backend for Linux and macOS

- Owner: sCrypt
- The boundary is already where it needs to be: system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, plus the WinFsp layer and the mount-point selector. Everything above them — the
  container format, the logical filesystem, the password widget — is platform-independent already.
  Real work, no design risk.

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
