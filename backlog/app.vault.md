# Swag Vault Backlog

This file is the product backlog for Swag Vault: what the application must gain to stand next to a
mature disk-encryption tool. It is scoped to this module and to the `bin/std` primitives Swag Vault
depends on.

Evidence, investigations, and intended outcomes owned by the application stay together here.
Operating-system work belongs in [platform.portability.md](platform.portability.md), and crypto throughput belongs
in [compiler.optimization.md](compiler.optimization.md); compiler and language work belongs in
[compiler.core.md](compiler.core.md) and [language.design.md](language.design.md). [README.md](README.md) has the whole
layout.


Locked key memory is a standard-library primitive that happens to have been discovered here; it
must not be reimplemented locally. The roadmap keeps the product adoption and its observable
security result together, while a standalone standard-library optimization belongs to the owning
module's roadmap.

### app.vault.002 — Unmounting has no explicit busy-versus-force contract

- Evidence: `WinFspMount.stop` stops the dispatcher, removes the mount point and destroys the
  filesystem with no busy result or force parameter.
- Next: define an ordinary unmount that reports open handles, and a forced unmount with
  confirmation and outstanding-I/O cancellation.
- Done when: unmounting a busy volume reports it instead of proceeding, and a forced unmount
  cancels outstanding I/O and returns a truthful result.

### app.vault.007 — No normative container-format specification

- Evidence: [hidden-volumes.md](../bin/apps/modules/swagvault/hidden-volumes.md) documents the
  version-1 hidden-locator extension; the base layout is described only by comments in
  `volume/format.swg`, `keyslot.swg` and `journal.swg`.
- Next: write a format document independent of the implementation covering layout, key
  derivation, record framing, validation order, versioning and failure indistinguishability.
- Done when: an independent implementer can read and validate a container from the document
  alone.
- Related: app.vault.008, app.vault.009, app.vault.010, app.vault.011, app.vault.012

### app.vault.003 — Additional password slots are not in the interface

- Evidence: `Volume.addPassword` and `Volume.removePassword` have no interface caller, so the
  interface only ever rewrites the password a reader opened with, although a version-1 container
  holds four key slots (`KeySlotCount`). Exposing them needs no format change.
- Next: add a key-slot list that adds and revokes passwords and shows how many slots are
  occupied without revealing which password maps to which slot.
- Done when: a user can add, use and revoke a second password from the interface, and a full
  container refuses a fifth with a clear message.

### app.vault.004 — Header backup and restore

- Evidence: key slots and both alternating headers live in the same file; damage to the only
  usable key slot or to both headers makes intact data inaccessible.
- Next: add interface commands to export and restore an independent encrypted header file that
  includes the key-slot area, documenting that a restore reinstates the passwords current at
  backup time.
- Done when: a container whose headers and key slots were overwritten opens again after restore,
  and the interface warns about reinstated passwords.

### app.vault.010 — Crash tests do not interrupt writes and checkpoints

- Evidence: `volume.test.swg` mutates completed files (corrupted journal records, alternating
  headers, misplaced sequences); no test interrupts an actual write.
- Next: add deterministic partial-write injection and process termination during checkpoint
  persistence.
- Done when: every injected interruption point reopens to a consistent earlier or later state.
- Related: app.vault.007

### app.vault.011 — Large metadata has no end-to-end scale benchmark

- Evidence: `nodeindex.test.swg` exercises 100,000 in-memory nodes and `volume.test.swg` crosses
  metadata paging with 300 nodes; nothing runs a durable container at that scale.
- Next: add a bounded end-to-end run at 100,000 files covering creation, reopen, lookup,
  enumeration, checkpointing, deletion and memory usage.
- Done when: the run is correct and reports time and peak memory for each phase.
- Related: app.vault.001, app.vault.007

### app.vault.001 — No block cache

- Evidence: `Volume.readPhysical` decrypts and verifies the tag on every call, so repeated reads
  pay authentication again and an unaligned write costs a read, decrypt, encrypt and write.
- Next: add a bounded LRU cache of decrypted blocks held in locked memory, wiped at unmount, with
  an explicit memory budget.
- Done when: repeated reads of a cached block skip decryption, the cache never exceeds its
  budget, and unmount wipes it.

### app.vault.005 — Filesystem mutations still use one volume-wide lock

- Evidence: reads take the shared side of `accessLock`, but mutating callbacks take its exclusive
  side, so writes to independent files cannot overlap.
- Next: write a concurrent mutation stress test, then replace the exclusive side with per-node
  locks plus a metadata lock.
- Done when: writes to independent files overlap and the stress test stays correct.

### app.vault.008 — No published Swag Vault format test vectors

- Next: publish deterministic vectors for key derivation, headers, records, locators and full
  minimal containers.
- Done when: the vectors ship with the format document and a test checks the implementation
  against them.
- Related: app.vault.007, app.vault.012

### app.vault.009 — Attacker-controlled container decoders are not fuzzed

- Next: fuzz `Volume.restore`, `Volume.loadNodes`, `Node.deserialize` and `JournalRecord.decode`
  with reproducible corpora and sanitizer coverage.
- Done when: each decoder has a reproducible fuzz corpus and every crash found is fixed with a
  regression input.
- Related: app.vault.007, app.vault.012

### app.vault.012 — External audit

- Evidence: neither the format nor the implementation has had independent review, so Swag Vault
  is not a proven replacement for VeraCrypt on critical data.
- Next: commission an external audit once app.vault.007 provides the format document.
- Done when: an independent audit report is published and its findings are resolved.
- Related: app.vault.007

---
