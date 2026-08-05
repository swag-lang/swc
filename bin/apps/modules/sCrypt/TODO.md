# sCrypt Roadmap

This file is the product roadmap for sCrypt: what the application must gain to stand next to a
mature disk-encryption tool. It is scoped to this module and to the `bin/std` primitives sCrypt
depends on.

It is not the repository's discovery backlog. Compiler, language, and general standard-library
leads belong in the root [TODO.md](../../../../TODO.md), which already carries the sCrypt
working-set entry. Keep the two separate: this file holds intent about the product, the root file
holds evidence about the platform.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Several entries are owned by `bin/std` rather than by sCrypt. Locked key memory is a
standard-library primitive that happens to have been discovered here; it must not be reimplemented
locally.

---

## Tier A — Throughput and credibility

### 1. No block cache

- Owner: sCrypt
- Problem: `Volume.readPhysical` reads 4124 bytes, decrypts, and verifies the tag on every single
  call, with no memory between calls. An unaligned write costs a read, a decrypt, an encrypt and a
  write. A sequential 1 MiB read is 256 separate 4 KiB I/O operations that are never coalesced.
- Fix: a bounded LRU cache of decrypted blocks, held in locked memory and wiped at unmount;
  coalescing of physically contiguous blocks into single I/O operations; and batched block
  decryption parallelized with `Jobs`. This is where the five-to-tenfold throughput factor is.
- Related: the working-set entry in the root TODO.md. A bounded cache is also the natural place to
  put an explicit memory budget, which that investigation will need.

### 2. The crypto primitives are scalar

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Problem: `chacha20.swg`, `poly1305.swg` and `argon2.swg` are all straightforward scalar
  implementations. Argon2id measures 403 ms at the Interactive profile and 2 396 ms at the Moderate
  default (release build, m=256 MiB, t=3, p=4), and rejecting a wrong password costs that four
  times over, because every key slot is probed whether or not it holds a password.
- Evidence: `compress` in `argon2.swg` is sixteen permutation passes of 64-bit mixing per 1 KiB
  block, and `chacha20Block` produces one 64-byte block at a time.
- Fix: given the repository's AVX work, the ChaCha20 quarter-round and the Argon2 permutation both
  vectorize directly. Argon2's lanes are also independent within a slice, so `Jobs` can run
  `parallelism` of them at once.
- Why it matters: the mount latency a user actually feels is almost entirely this.

### 3. Keys live in pageable memory

- Owner: `bin/std` for the locked allocation, sCrypt for the policy
- Problem: `Crypto.Keys` and the unwrapped master key are ordinary memory. The page file or a crash
  minidump can capture the master key. VeraCrypt locks its key pages.
- Fix: `VirtualLock` on key pages, exclusion from Windows Error Reporting dumps, and key wipe on
  session lock and on system suspend. Small surface, large credibility return.

### 4. The executable is not signed

- Owner: release process
- Problem: the application requests UAC elevation to start the driver. Unsigned, the consent dialog
  reads "Unknown publisher" for an encryption tool. This is a larger adoption obstacle than any
  feature on this list.
- Fix: an OV or EV code-signing certificate, applied to `sCrypt.exe`.
- Note: elevation is only required because the portable WinFsp driver has to be registered by the
  guardian process. A system-wide WinFsp installation makes `loadWinFsp` take the installed runtime
  and skip the guardian entirely, which is also what allows an automated end-to-end test loop
  without a consent dialog on every run.

### 5. Container creation draws every byte from the system CSPRNG

- Owner: sCrypt
- Problem: `Volume.create` fills the whole container through `Core.Crypto.randomBytes` in 1 MiB
  chunks, which routes every byte through `BCryptGenRandom`. A 100 GiB container means 100 GiB of
  system CSPRNG output.
- Fix: draw a 32-byte seed, produce the fill from a ChaCha20 keystream, and discard the seed. The
  result is statistically indistinguishable from random and five to twenty times faster.
- Also: the fill loop cannot currently be interrupted. Add progress reporting and cancellation.

---

## Tier B — Perceived feature parity

### 6. Mount comfort and mount-time safety

- Owner: sCrypt
- Problem: one volume, one drive letter, no options. Missing: read-only mount, multiple concurrent
  volumes, favorites, mount at logon, and forced unmount — plus automatic unmount on session lock,
  on suspend, and on idle, which is a security feature rather than a convenience.
- Why it ranks here: this is the bulk of the *perceived* gap against VeraCrypt, at moderate cost.

### 7. Password management is not in the interface

- Owner: sCrypt
- Problem: `Volume.changePassword`, `Volume.addPassword` and `Volume.removePassword` exist and are
  tested, but nothing in `mainwindow.swg` or `vaultcard.swg` reaches them. The capability ships
  without a way to use it.
- Fix: a key-slot panel on the vault card — change password, add a password, revoke one, and a
  cost-profile selector backed by `Crypto.Argon2Profile`.
- Note: `KeySlotCount` is 4. Raising it costs one constant and a wider `keySlotMask`, but it also
  multiplies the cost of rejecting a wrong password; see entry 2.

### 8. Resize

- Owner: sCrypt
- Problem: capacity is fixed in `Volume.create` and cannot change.
- Fix: growing is straightforward — extend the file, fill the new region with random bytes, update
  `blockCount` and `containerSize`, and checkpoint. Note that `restore` cross-checks `storedSize`
  against the actual file size, so the growth must be a committed operation rather than an external
  file extension. The free list is derived from what the node table references, so nothing else has
  to be rewritten.
- Shrinking requires evacuating blocks above the new limit: more work, less value, defer it.

### 9. Header backup and restore

- Owner: sCrypt
- Problem: the key slots and both header slots live in the same file, in its first megabytes. One
  bad sector there destroys the whole container, including data blocks that are perfectly intact.
- Fix: export and restore of an independent encrypted header file, exposed in the interface. The
  export must cover the key slot area as well, because that is now where the master key lives.
- Document the trap VeraCrypt also documents: restoring a backed-up header reinstates the passwords
  that were current when the backup was taken.

### 10. Keyfiles

- Owner: sCrypt
- Key slots exist, so this is now only mixing: the slot key derives from the password combined with
  a hash of the keyfiles, under a deterministic ordering. `Core.Crypto.argon2id` already accepts a
  secret and an associated-data input for exactly this. PKCS#11 tokens are a further step and can
  wait.

### 11. Randomized block allocation

- Owner: sCrypt
- Problem: `BlockAllocator.allocate` always returns the lowest free block. An adversary comparing
  two snapshots of a container learns exactly which blocks changed and in what order, and therefore
  the sizes and sequence of writes.
- Fix: pick randomly within the free list. A few lines, and it blurs the signal considerably.
- Note: this now also applies to metadata pages, which are allocated the same way at every
  checkpoint.

### 12. Concurrency

- Owner: sCrypt
- Problem: WinFsp runs under the coarse guard strategy, so every callback is serialized and all
  encryption for a large copy sits on one thread.
- Fix: finer granularity — a per-node lock plus a metadata lock — and block encryption parallelized
  through `Jobs`.
- Sequencing: after entry 1, and only alongside a concurrent stress test. Getting this wrong is a
  correctness failure, not a performance regression.

---

## Tier C — Long term

### 13. Hidden volume

- Owner: sCrypt
- The format already permits it: the container is entirely random, carries no magic, and derives
  its record locators from the key (`Crypto.recordLocator`). A second key slot area and header at a
  key-derived offset hide naturally.
- The real work is not the format. It is the protect-hidden-volume mode, where the outer volume
  must refuse writes into the hidden region without ever revealing that the region exists, and the
  interface for that constraint.
- Sequencing: last. A hidden volume that leaks is worse than no hidden volume, because it promises
  a protection it does not deliver.

### 14. Format specification, test vectors, fuzzing

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

### 15. FUSE backend for Linux and macOS

- Owner: sCrypt
- The README already describes the boundary: system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, plus the WinFsp layer and the mount-point selector. Real work, no design risk.

### 16. External audit

- Owner: project
- After entry 14. Until it happens, the caveat in `README.md` stays true no matter what else on
  this list ships.

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
