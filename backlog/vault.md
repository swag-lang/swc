# Swag Vault Backlog

This file is the product backlog for Swag Vault: what the application must gain to stand next to a
mature disk-encryption tool. It is scoped to this module and to the `bin/std` primitives Swag Vault
depends on.

Evidence, investigations, and intended outcomes owned by the application stay together here.
Operating-system work belongs in [portability.md](portability.md), and crypto throughput belongs
in [optimization.md](optimization.md); compiler and language work belongs in
[compiler.md](compiler.md) and [language.md](language.md). [README.md](README.md) has the whole
layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Locked key memory is a standard-library primitive that happens to have been discovered here; it
must not be reimplemented locally. The roadmap keeps the product adoption and its observable
security result together, while a standalone standard-library optimization belongs to the owning
module's roadmap.

---

## Tier A — Block I/O throughput

### B-236 — No block cache

- Owner: Swag Vault
- Problem: `Volume.readPhysical` decrypts and verifies the tag on every call, with no memory
  between calls. Repeated reads still pay authentication and decryption, and an unaligned write
  still costs a read, a decrypt, an encrypt and a write.
- Fix: a bounded LRU cache of decrypted blocks, held in locked memory and wiped at unmount.
- Related: a bounded cache is also the natural place to put an explicit memory budget, which any
  later working-set investigation will need.




---

## Tier B — Automatic and forced unmounting

### B-239 — A busy volume cannot be forcibly unmounted

- Owner: Swag Vault
- Add an explicit forced-unmount flow when an open handle keeps a volume busy, including user
  confirmation, outstanding-I/O cancellation, and a truthful result.
- Note: the startup list is persisted with `needsPassword` beside each path, which is what keeps a
  start quiet for an unprotected vault. It is not a hint an attacker could not obtain in one Argon2
  attempt, but it does mean the state file says which vaults have no password.

## Tier B — Credentials

### B-240 — Additional password slots are not in the interface

- Owner: Swag Vault
- Problem: `Volume.addPassword` and `Volume.removePassword` still have no way in. A container can
  hold four passwords and the interface only ever writes the one a reader opened it with.
- Fix: a key-slot list that can add and revoke passwords and show how many slots are occupied
  without claiming which password maps to which slot.
- Note: `KeySlotCount` is 4. Version 4 derives one slot key per password attempt and then checks
  every slot cheaply, so raising the count costs one constant and a wider `keySlotMask` without
  multiplying the Argon2 cost.

## Tier B — Container maintenance

### B-241 — Header backup and restore

- Owner: Swag Vault
- Problem: the key slots and both header slots live in the same file, in its first megabytes. One
  bad sector there destroys the whole container, including data blocks that are perfectly intact.
- Fix: export and restore of an independent encrypted header file, exposed in the interface. The
  export must cover the key slot area as well, because that is now where the master key lives.
- Document the trap VeraCrypt also documents: restoring a backed-up header reinstates the passwords
  that were current when the backup was taken.

## Tier B — Filesystem concurrency

### B-242 — Filesystem mutations still use one volume-wide lock

- Owner: Swag Vault
- Problem: WinFsp now uses its fine guard, reads can proceed concurrently, and large transfers run
  bounded parallel crypto batches. Mutating callbacks still take one volume-wide exclusive lock,
  so writes to independent files cannot overlap.
- Fix: replace the exclusive side with per-node locks plus a metadata lock.
- Sequencing: only alongside a concurrent stress test. Getting this wrong is a correctness failure,
  not a performance regression.

---

## Tier C — Format design and resilience

### B-243 — Hidden volume

- Owner: Swag Vault
- The format already permits it: the container is entirely random, carries no magic, and derives
  its record locators from the key (`Crypto.recordLocator`). A second key slot area and header at a
  key-derived offset hide naturally.
- The real work is not the format. It is the protect-hidden-volume mode, where the outer volume
  must refuse writes into the hidden region without ever revealing that the region exists, and the
  interface for that constraint.
- Sequencing: last. A hidden volume that leaks is worse than no hidden volume, because it promises
  a protection it does not deliver.

### B-244 — No normative container-format specification

- Owner: Swag Vault
- Write a normative format document independent of the implementation, covering layout, key
  derivation, record framing, validation order, versioning, and failure indistinguishability.
- Related: B-360, B-361, B-362, B-363, B-246

### B-360 — No published Swag Vault format test vectors

- Owner: Swag Vault
- Publish deterministic vectors for key derivation, headers, records, locators, and full minimal
  containers so independent implementations can be compared.
- Related: B-244, B-246

### B-361 — Attacker-controlled container decoders are not fuzzed

- Owner: Swag Vault
- Fuzz `Volume.restore`, `Volume.loadNodes`, `Node.deserialize`, and `JournalRecord.decode` with
  reproducible corpora and sanitizer coverage.
- Related: B-244, B-246

### B-362 — Crash tests do not cover torn records or checkpoint kills

- Owner: Swag Vault
- Extend crash consistency beyond between-operation snapshots to torn writes inside a record and
  process termination during checkpointing.
- Related: B-244

## Tier C — Scale and independent assurance

### B-363 — Metadata scaling stops at 1,200 files

- Owner: Swag Vault
- Add a bounded performance and correctness test at one hundred thousand files.
- Related: B-236, B-244



### B-246 — External audit

- Owner: project
- After B-244. Until it happens, the format and the implementation have had no independent
  cryptographic review, and Swag Vault is not a proven replacement for VeraCrypt on critical data — no
  matter what else on this list ships.

---

## Out of scope

**Partition and system-disk encryption.** WinFsp is a filesystem proxy, not a volume driver.
Supporting this means writing a kernel-mode virtual disk driver and a pre-boot authenticator: a
different product, and one that destroys the portable, no-installation property that is currently
Swag Vault's genuine advantage. This is a case where a mature block-level tool is simply the right
answer, and Swag Vault should say so rather than chase it.

**Cipher cascades and a user-facing cipher menu.** Format agility yes; a dropdown no. Cascades are
theatre; they triple the bug surface for no defensible gain over a correctly implemented modern
AEAD. The format carries a version, so changing algorithm later stays possible without exposing the
choice.

**Reading a container older than format version 3.** Version 3 replaced the key schedule, the KDF
and the record framing at once, so nothing an earlier version wrote can be read without a parallel
implementation of all three. The container also reports the same outcome for a wrong password, a
damaged container and an older format, deliberately: telling them apart is exactly what the design
refuses to do.
