# Swag Vault Backlog

This file is the product backlog for Swag Vault: what the application must gain to stand next to a
mature disk-encryption tool. It is scoped to this module and to the `bin/std` primitives Swag Vault
depends on.

Evidence, investigations, and intended outcomes owned by the application stay together here.
Operating-system work belongs in [platform.portability.md](platform.portability.md), and crypto throughput belongs
in [compiler.optimization.md](compiler.optimization.md); compiler and language work belongs in
[compiler.core.md](compiler.core.md) and [language.design.md](language.design.md). [README.md](README.md) has the whole
layout.

Entries are ordered from the most recently updated down. An entry disappears when it
ships; history lives in git, not here.

Locked key memory is a standard-library primitive that happens to have been discovered here; it
must not be reimplemented locally. The roadmap keeps the product adoption and its observable
security result together, while a standalone standard-library optimization belongs to the owning
module's roadmap.

### app.vault.002 — Unmounting has no explicit busy-versus-force contract

- Recorded: 2026-08-06 08:32
- Updated: 2026-09-06 07:51 — git: prompt 6
- Owner: Swag Vault
- Current `WinFspMount.stop` stops the dispatcher, removes the mount point, and destroys the
  filesystem without a busy-result or force parameter. Define an ordinary unmount result for
  open handles and an explicit forced-unmount flow, including confirmation, outstanding-I/O
  cancellation, and a truthful result.
- Note: the startup list is persisted with `needsPassword` beside each path, which is what keeps a
  start quiet for an unprotected vault. It is not a hint an attacker could not obtain in one Argon2
  attempt, but it does mean the state file says which vaults have no password.

### app.vault.003 — Additional password slots are not in the interface

- Recorded: 2026-08-06 08:32
- Updated: 2026-09-06 07:51 — git: prompt 6
- Owner: Swag Vault
- Problem: `Volume.addPassword` and `Volume.removePassword` still have no way in. A container can
  hold four passwords and the interface only ever writes the one a reader opened it with.
- Fix: a key-slot list that can add and revoke passwords and show how many slots are occupied
  without claiming which password maps to which slot.
- Note: the current format version is 1 and `KeySlotCount` is fixed at four. A password attempt
  performs one Argon2id derivation followed by four authenticated opens. Changing the slot count
  would change the physical header/data offsets and requires a format decision; it is not needed
  to expose the four existing slots.

### app.vault.004 — Header backup and restore

- Recorded: 2026-08-06 08:32
- Updated: 2026-09-06 07:51 — git: prompt 6
- Owner: Swag Vault
- Problem: key slots and both alternating headers live in the same file. Damage to the only
  usable password slot or to both header copies can make otherwise intact data inaccessible.
  A damaged header alone can already fall back to the other checkpoint and replay the journal.
- Fix: export and restore of an independent encrypted header file, exposed in the interface. The
  export must cover the key slot area as well, because that is now where the master key lives.
- Document the trap VeraCrypt also documents: restoring a backed-up header reinstates the passwords
  that were current when the backup was taken.

### app.vault.010 — Crash tests do not interrupt writes and checkpoints

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-06 07:51 — git: prompt 6
- Owner: Swag Vault
- `volume.test.swg` already corrupts a journal record and verifies that replay stops before later
  records; it also checks alternating-header recovery and misplaced journal sequences. These are
  completed-file mutations. Add deterministic partial-write injection and process termination
  during checkpoint persistence to exercise the ordering of actual writes.
- Related: app.vault.007

### app.vault.011 — Large metadata has no end-to-end scale benchmark

- Recorded: 2026-08-06 08:32
- Updated: 2026-09-06 07:51 — git: prompt 6
- Owner: Swag Vault
- `nodeindex.test.swg` already exercises 100,000 in-memory nodes, and `volume.test.swg` crosses
  metadata paging with 300 nodes using smaller test headers. Add a bounded end-to-end correctness
  and performance run at 100,000 files, covering durable creation, reopen, lookup, enumeration,
  checkpointing, deletion, and memory usage.
- Related: app.vault.001, app.vault.007

### app.vault.001 — No block cache

- Recorded: 2026-08-06 08:32
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Problem: `Volume.readPhysical` decrypts and verifies the tag on every call, with no memory
  between calls. Repeated reads still pay authentication and decryption, and an unaligned write
  still costs a read, a decrypt, an encrypt and a write.
- Fix: a bounded LRU cache of decrypted blocks, held in locked memory and wiped at unmount.
- Related: a bounded cache is also the natural place to put an explicit memory budget, which any
  later working-set investigation will need.

### app.vault.005 — Filesystem mutations still use one volume-wide lock

- Recorded: 2026-08-06 08:32
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Problem: WinFsp now uses its fine guard, reads can proceed concurrently, and large transfers run
  bounded parallel crypto batches. Mutating callbacks still take one volume-wide exclusive lock,
  so writes to independent files cannot overlap.
- Fix: replace the exclusive side with per-node locks plus a metadata lock.
- Sequencing: only alongside a concurrent stress test. Getting this wrong is a correctness failure,
  not a performance regression.

### app.vault.007 — No normative container-format specification

- Recorded: 2026-08-06 08:32
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Write a normative format document independent of the implementation, covering layout, key
  derivation, record framing, validation order, versioning, and failure indistinguishability.
- Related: app.vault.008, app.vault.009, app.vault.010, app.vault.011, app.vault.012

### app.vault.008 — No published Swag Vault format test vectors

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Publish deterministic vectors for key derivation, headers, records, locators, and full minimal
  containers so independent implementations can be compared.
- Related: app.vault.007, app.vault.012

### app.vault.009 — Attacker-controlled container decoders are not fuzzed

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: Swag Vault
- Fuzz `Volume.restore`, `Volume.loadNodes`, `Node.deserialize`, and `JournalRecord.decode` with
  reproducible corpora and sanitizer coverage.
- Related: app.vault.007, app.vault.012

### app.vault.012 — External audit

- Recorded: 2026-08-06 08:32
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Owner: project
- After app.vault.007. Until it happens, the format and the implementation have had no independent
  cryptographic review, and Swag Vault is not a proven replacement for VeraCrypt on critical data — no
  matter what else on this list ships.

---

## Out of scope

**Partition and system-disk encryption.** The application hosts a filesystem through WinFsp.
A block-device and pre-boot encryption product would require a different driver, boot integration,
and recovery contract. The bundled WinFsp path already uses an elevated helper to register its
signed runtime; describing the application as requiring no driver setup would be inaccurate.

**Cipher cascades and a user-facing cipher menu.** Keep the cryptographic suite part of the
versioned format contract. A user-facing algorithm menu and cascade combinations are outside the
product scope; future suite changes require format compatibility and independent review.

**Reading an incompatible historical format.** The current decoder accepts format version 1 of
its present key-slot and record layout. Earlier layouts require separate decoders and an explicit
migration contract. Unsupported layout, wrong password, and damaged authentication records retain
the format's deliberately indistinguishable unlock failure.
