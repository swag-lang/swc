# sCrypt Roadmap

This file is the product roadmap for sCrypt: what the application must gain to stand next to a
mature disk-encryption tool. It is scoped to this module and to the `bin/std` primitives sCrypt
depends on.

It is not the repository's discovery backlog. Platform leads and defects belong in
[FINDINGS.md](../../../../FINDINGS.md), which already carries the sCrypt working-set entry;
compiler and language intent belongs in the root [TODO.md](../../../../TODO.md). Keep them
separate: this file holds intent about the product, `FINDINGS.md` holds evidence about the
platform.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Items 3, 4 and 5 are a single on-disk format change and must land together as format version 3.
Splitting them would cost three migrations instead of one. `LegacyFormatVersion` in
`src/volume/format.swg` shows the migration mechanism already works.

Several entries are owned by `bin/std` rather than by sCrypt. Argon2id, a one-pass AEAD, and
locked key memory are standard-library primitives that happen to have been discovered here; they
must not be reimplemented locally.

---

## Tier A — The walls

### 1. Commit is O(N) per metadata operation, so populating a volume is O(N squared)

- Owner: sCrypt
- Problem: `createNode`, `deleteNode`, `renameNode`, `callbackOverwrite`, `callbackCleanup` and
  `callbackSetVolumeLabel` all call `Volume.commit`, which calls `Volume.serialize`. That method
  re-serializes the entire node table, every block run of every node, and the whole free list,
  then encrypts and authenticates the result and writes it.
- Evidence: `src/volume/volume.swg` — `commit` at the `serialize(newSequence)` call, and the
  `for node in .nodes` loop in `serialize`. Copying ten thousand files produces roughly 2.5 MiB of
  final metadata, but writes on the order of 10 GiB, because every one of the ten thousand commits
  rewrites the whole blob. NTFS inside a block-level container writes a few sectors of MFT and
  journal for the same work.
- Fix: an intent journal. Each mutation appends a small encrypted record, on the order of a few
  hundred bytes, to a circular journal area. The full header is rewritten only at a checkpoint —
  every N records, or at unmount. Opening a volume loads the checkpoint and replays the journal.
  The existing two-slot alternation stays exactly as it is and becomes the atomic commit mechanism
  for the checkpoint rather than for every operation.
- Format impact: yes, but independent of the version 3 crypto change; it can ship before or after.

### 2. Hard ceiling on file count, and copy-on-write lowers it over time

- Owner: sCrypt
- Problem: all metadata lives in one header slot. `HeaderPlainSize` is about 8 MiB in production.
  A node costs roughly 250 bytes before its block map — id, parent id, sized name, attributes,
  size, four timestamps, and a Windows self-relative security descriptor — plus 24 bytes per
  extent run. `MaximumNodeCount` is set to one million, which is unreachable: the real wall is on
  the order of thirty thousand files, and far fewer once files fragment.
- Evidence: `src/volume/format.swg` for the sizes, and the `failWith("The encrypted metadata area
  is full.", .DiskFull)` guard at the end of `serialize`. The ceiling drops with use because
  `Volume.writeBlock` always allocates a fresh physical block and `BlockAllocator.allocate` always
  takes the lowest free block, so every rewrite fragments the file and grows its run list. The
  user-visible symptom is a disk-full error on a volume with gigabytes of free blocks. Under
  `swc test` the slot is 256 KiB, thirty-two times smaller, and still no test reaches the wall.
- Fix: page the metadata into encrypted data blocks — indexed node pages, or a B-tree — and keep
  only the root in the header. Entry 1 should land first; it removes the write amplification and
  makes this change far smaller.
- Format impact: yes.

### 3. The encryption key is the password-derived key

- Owner: sCrypt
- Problem: `Crypto.deriveKeys` in `src/volume/crypto.swg` produces the encryption and
  authentication keys directly from the password and salt. Nothing sits between them. Changing the
  password therefore requires rewriting the entire container, only one password can ever exist, a
  keyfile cannot be added after creation, and nothing can be revoked.
- Fix: an independent master key with key slots, as LUKS and VeraCrypt do. Generate a random
  64-byte master key at creation and never derive it. Store N slots, each holding a salt, its KDF
  parameters, and the master key wrapped by the key derived from that slot's password. Changing a
  password becomes a hundred-byte write.
- Why it ranks this high: it is the architectural unlock for three separate features — password
  change, keyfiles, and multiple passwords. None of them are reachable without it.
- Format impact: yes — version 3, together with entries 4 and 5.

### 4. PBKDF2-HMAC-SHA-256 is the wrong KDF

- Owner: `bin/std` (`bin/std/modules/core/src/crypto/`)
- Problem: `Crypto.KdfIterations` is 200 000 iterations of PBKDF2-HMAC-SHA-256. SHA-256 is the most
  heavily optimized primitive in existence on GPU and ASIC, and PBKDF2 has no memory cost, so the
  attack parallelizes without limit. A human-chosen password of eight to ten characters does not
  survive a motivated adversary.
- Fix: Argon2id, RFC 9106, alongside the existing `pbkdf2.swg`. Sensible defaults are m=256 MiB,
  t=3, p=4. Parameters are stored per key slot, which is why this is coupled to entry 3.
- Note: VeraCrypt has the same weakness, so this is not a parity gap — it is the one place where
  sCrypt can be straightforwardly better than the tool it is compared against.
- Format impact: yes — version 3.

### 5. Two crypto passes per block in each direction

- Owner: `bin/std` for the primitive, sCrypt for the record format
- Problem: `Crypto.seal` and `Crypto.open` run ChaCha20 and then HMAC-SHA-256, so every 4 KiB block
  is traversed twice on write and twice on read. The tag costs 32 bytes per block.
- Fix: a single-pass AEAD. ChaCha20-Poly1305 (RFC 8439), or AES-256-GCM, which is materially faster
  on x64 with AES-NI and PCLMULQDQ. The tag drops to 16 bytes, so `BlockRecordSize` falls from 4140
  to 4124 and the per-block overhead shrinks with it.
- Also: check whether `bin/std/modules/core/src/crypto/chacha20.swg` is vectorized. Given the
  repository's AVX work, there is likely headroom there regardless of which AEAD is chosen.
- Constraint: add an algorithm identifier field for format agility, but do not add a cipher choice
  to the user interface and do not add cascades. Cascades are theatre; they triple the bug surface
  for no defensible gain over a correctly implemented modern AEAD.
- Format impact: yes — version 3.

---

## Tier B — Throughput and credibility

### 6. No block cache

- Owner: sCrypt
- Problem: `Volume.readPhysical` reads 4140 bytes, decrypts, and verifies the tag on every single
  call, with no memory between calls. An unaligned write costs a read, a decrypt, an encrypt and a
  write. A sequential 1 MiB read is 256 separate 4 KiB I/O operations that are never coalesced.
- Fix: a bounded LRU cache of decrypted blocks, held in locked memory and wiped at unmount;
  coalescing of physically contiguous blocks into single I/O operations; and batched block
  decryption parallelized with `Jobs`. This is where the five-to-tenfold throughput factor is.
- Related: the working-set entry in `FINDINGS.md`. A bounded cache is also the natural place to
  put an explicit memory budget, which that investigation will need.

### 7. Keys live in pageable memory

- Owner: `bin/std` for the locked allocation, sCrypt for the policy
- Problem: `Crypto.Keys` is ordinary memory. The page file or a crash minidump can capture the
  master key. VeraCrypt locks its key pages.
- Fix: `VirtualLock` on key pages, exclusion from Windows Error Reporting dumps, and key wipe on
  session lock and on system suspend. Small surface, large credibility return.

### 8. The executable is not signed

- Owner: release process
- Problem: the application requests UAC elevation to start the driver. Unsigned, the consent dialog
  reads "Unknown publisher" for an encryption tool. This is a larger adoption obstacle than any
  feature on this list.
- Fix: an OV or EV code-signing certificate, applied to `sCrypt.exe`.

### 9. Container creation draws every byte from the system CSPRNG

- Owner: sCrypt
- Problem: `Volume.create` fills the whole container through `Core.Crypto.randomBytes` in 1 MiB
  chunks, which routes every byte through `BCryptGenRandom`. A 100 GiB container means 100 GiB of
  system CSPRNG output.
- Fix: draw a 32-byte seed, produce the fill from a ChaCha20 keystream, and discard the seed. The
  result is statistically indistinguishable from random and five to twenty times faster.
- Also: the fill loop cannot currently be interrupted. Add progress reporting and cancellation.

---

## Tier C — Perceived feature parity

### 10. Mount comfort and mount-time safety

- Owner: sCrypt
- Problem: one volume, one drive letter, no options. Missing: read-only mount, multiple concurrent
  volumes, favorites, mount at logon, and forced unmount — plus automatic unmount on session lock,
  on suspend, and on idle, which is a security feature rather than a convenience.
- Why it ranks here: this is the bulk of the *perceived* gap against VeraCrypt, at moderate cost.

### 11. Resize

- Owner: sCrypt
- Problem: capacity is fixed in `Volume.create` and cannot change.
- Fix: growing is straightforward — extend the file, fill the new region with random bytes, add the
  new range to the free list, update `blockCount` and `containerSize`, and commit. Note that
  `deserialize` cross-checks `storedSize` against the actual file size, so the growth must be a
  committed operation rather than an external file extension.
- Shrinking requires evacuating blocks above the new limit: more work, less value, defer it.

### 12. Header backup and restore

- Owner: sCrypt
- Problem: both header slots live in the same file, inside the first 16 MiB. One bad sector there
  destroys the whole container, including data blocks that are perfectly intact.
- Fix: export and restore of an independent encrypted header file, exposed in the interface.
- Document the trap VeraCrypt also documents: restoring a backed-up header reinstates the password
  that was current when the backup was taken.

### 13. Keyfiles

- Owner: sCrypt
- Depends on entry 3. Once key slots exist, this is mixing: the slot key derives from the password
  combined with a hash of the keyfiles, under a deterministic ordering. PKCS#11 tokens are a
  further step and can wait.

### 14. Randomized block allocation

- Owner: sCrypt
- Problem: `BlockAllocator.allocate` always returns the lowest free block. An adversary comparing
  two snapshots of a container learns exactly which blocks changed and in what order, and therefore
  the sizes and sequence of writes.
- Fix: pick randomly within the free list. A few lines, and it blurs the signal considerably.

### 15. Concurrency

- Owner: sCrypt
- Problem: WinFsp runs under the coarse guard strategy, so every callback is serialized and all
  encryption for a large copy sits on one thread.
- Fix: finer granularity — a per-node lock plus a metadata lock — and block encryption parallelized
  through `Jobs`.
- Sequencing: after entry 6, and only alongside a concurrent stress test. Getting this wrong is a
  correctness failure, not a performance regression.

---

## Tier D — Long term

### 16. Hidden volume

- Owner: sCrypt
- The format already permits it: the container is entirely random, carries no magic, and derives
  its header locator from the key (`Crypto.recordLocator`). A second header at a key-derived offset
  hides naturally.
- The real work is not the format. It is the protect-hidden-volume mode, where the outer volume
  must refuse writes into the hidden region without ever revealing that the region exists, and the
  interface for that constraint.
- Sequencing: last. A hidden volume that leaks is worse than no hidden volume, because it promises
  a protection it does not deliver.

### 17. Format specification, test vectors, fuzzing

- Owner: sCrypt
- An audit is not possible without a normative format document that is independent of the code,
  plus published test vectors. Then:
  - Fuzz `Volume.deserialize`. Its own comment records that the plaintext is attacker-controlled
    once the password is known, so a maliciously crafted shared container is a real attack surface.
  - Add crash-consistency tests: kill the process mid-commit, reopen, verify. The two-slot design
    exists for exactly this and nothing currently exercises it.
  - Add a scaling test at a hundred thousand files, to lock in entries 1 and 2.

### 18. FUSE backend for Linux and macOS

- Owner: sCrypt
- The README already describes the boundary: system backends for `Core.Crypto`, `Core.Time` and
  `Core.File`, plus the WinFsp layer and the mount-point selector. Real work, no design risk.

### 19. External audit

- Owner: project
- After entry 17. Until it happens, the caveat in `README.md` stays true no matter what else on
  this list ships.

---

## Out of scope

**Partition and system-disk encryption.** WinFsp is a filesystem proxy, not a volume driver.
Supporting this means writing a kernel-mode virtual disk driver and a pre-boot authenticator: a
different product, and one that destroys the portable, no-installation property that is currently
sCrypt's genuine advantage. This is a case where a mature block-level tool is simply the right
answer, and sCrypt should say so rather than chase it.

**Cipher cascades and a user-facing cipher menu.** Format agility yes; a dropdown no. See entry 5.
