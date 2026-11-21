# Swag Vault container format

This document describes the production version-1 container format implemented by Swag Vault.
Multi-credential hidden-volume locators are an extension described in
[Hidden volumes](hidden-volumes.md). Test builds deliberately use smaller header and journal areas
and a cheaper password KDF; those test-only values are not part of the production format.

## Geometry

All offsets are relative to the start of a volume view. A hidden volume has its own view and uses
the same geometry relative to its authenticated base. Integer fields are little-endian.

| Area | Start | Size |
| --- | ---: | ---: |
| Four key slots | 0 | 1,024 bytes |
| Header slot 0 | 1,024 | 1 MiB |
| Header slot 1 | 1,049,600 | 1 MiB |
| Circular journal | 2,098,176 | 1 MiB |
| Data and metadata blocks | 3,146,752 | Remainder of the logical container |

Each data-area block is 4,124 bytes on disk: a 12-byte nonce, 4,096 bytes of ciphertext, and a
16-byte authentication tag. The header's `containerSize` is the logical capacity in bytes;
`blockCount` is `floor((containerSize - 3,146,752) / 4,124)`. A partial remainder smaller than one
record is unused. Production containers require at least 16 blocks, for a minimum logical size of
3,212,736 bytes.

For an ordinary container, the authenticated `physicalSize` includes a random camouflage tail;
the tail is not addressable storage. Production `Volume.create` chooses its length so the tail is
between these bounds:

* minimum: `min(max(8 MiB, logicalSize / 32), 512 MiB)`
* maximum: `min(max(64 MiB, logicalSize / 8), 2 GiB)`

Production creation randomizes the complete physical file before writing the initial records. A
hidden volume has no camouflage tail: its physical view length is exactly the authenticated hidden
range length. A shorter host region is rejected. After a committed size or camouflage update, a
writable open may truncate excess host bytes to the authenticated physical size, but only for an
ordinary view without active hidden-range protection. Hidden views do not use this recovery
truncation.

## Cryptographic construction

Production uses Argon2id with 262,144 KiB memory, three iterations, four lanes, and a 32-byte
output. The first 32 bytes of the key-slot area are the container-wide salt. Every password slot
uses that salt, so opening a password derives one key and tries the four slots. A hidden-volume
locator has its own random 32-byte salt and derives its key independently.
The empty password is valid and derives a slot key in the same way. With no key files, password
bytes are the KDF input. With ordered key files, the input is a 64-byte unkeyed BLAKE2b digest
over the ASCII domain `swag vault access key files v2`, the password length, the password bytes,
the key-file count, and each key file's length followed by its chunk digests in file order.
Lengths and counts are little-endian `u64` values.

Split each file into consecutive 1 MiB chunks, with a shorter final chunk if needed. Each chunk
contributes a 64-byte unkeyed BLAKE2b digest of its raw bytes. An empty file contributes its
zero length and no chunk digests. Moving a key file preserves its contribution. Outer password
slots and hidden-volume locators use this credential derivation. The Argon2id parameters are
fixed by the container format version.

The 64-byte master key is generated randomly. It is not derived from a password. A password-derived
32-byte slot key wraps the master key with ChaCha20-Poly1305. The master key is expanded into two
independent 32-byte keys with keyed BLAKE2b:

| Purpose | BLAKE2b message/context |
| --- | --- |
| Record encryption | `swag vault record key v1` |
| Record locators | `swag vault locator key v1` |

Every AEAD record uses a fresh 12-byte ChaCha20-Poly1305 nonce and a 16-byte tag. Its associated
data is exactly 12 bytes: the record-kind `u32`, then the record identifier as low and high `u32`
words, all little-endian. This binds ciphertext to its role and logical position.

| AEAD record | Kind | Record identifier |
| --- | ---: | --- |
| Header | 1 | Header slot index, 0 or 1 |
| Data block | 2 | Physical block index |
| Metadata page | 5 | Physical block index |
| Journal | 6 | Journal ring slot |
| Wrapped master key | 8 | Key-slot index, 0 through 3 |

Header and journal record locators use separate BLAKE2b kinds: 3 for a header slot and 7 for a
journal ring slot. The hidden-locator extension uses its own kind and is specified in
[Hidden volumes](hidden-volumes.md).

The record-locator value is a 16-byte keyed BLAKE2b result under the locator key. Its input is
the locator kind, identifier, and a fixed `loca` domain marker, encoded as four little-endian
`u32` words. Locators let a reader find a record without a public signature in its area.

## Key slots

The key-slot area contains four 256-byte slots. Each starts with 32 random bytes; the first slot's
prefix is the shared Argon2id salt. The following 92 bytes are the wrapped-key payload:

| Slot-relative offset | Size | Contents |
| ---: | ---: | --- |
| 0 | 32 | Random prefix; slot 0 stores the shared salt |
| 32 | 12 | ChaCha20-Poly1305 nonce |
| 44 | 64 | Encrypted master key |
| 108 | 16 | Authentication tag |
| 124 | 4 | Random bytes |
| 128 | 128 | Reserved for the optional hidden-volume locator |

The wrapped-key tag uses kind 8 and the slot index as associated data. The canonical encrypted
header uses the four low bits of a `u32` slot mask; the mask is not visible in the key-slot area.
The current reader does not reject upper bits or a zero mask. An initially created container
chooses one of the four slots uniformly. An interrupted password addition can reserve a slot
before its payload is written, so a set mask bit does not by itself prove that the slot unwraps a
key. Ordinary password changes write and verify a replacement before erasing the old slot.
`removePassword` requires a supplied password to authenticate a different active slot. This avoids
mistaking a reserved bit for the last usable way into the container.

## Framed records

Headers and journal entries use a variable-length encrypted record inside a fixed-size area. Its
28-byte prefix is a 16-byte locator followed by a 12-byte nonce. The stored locator consists of the
first 12 bytes of the computed locator, compared in constant time, followed by a little-endian
`u32` equal to `plaintext length XOR locator bytes 12–15`. The prefix is followed by ciphertext of
the decoded length and the 16-byte tag. The remainder of the fixed area is left as random or
previous bytes. The full locator is not stored.

Header areas are 1 MiB. Their maximum plaintext is 1,048,532 bytes. Journal areas contain 256
4,096-byte slots; each slot has at most 4,052 plaintext bytes. The same 28-byte prefix layout is
used for both, with the locator kind and record kind from the table above.

Data blocks and metadata pages do not use this prefix: each occupies exactly one block record of
4,124 bytes. They are located by geometry and authenticated by kind and physical block index.

## Header and metadata image

The header plaintext is written in this order:

1. 16-byte magic `SWAG-VAULT-V1` followed by three zero bytes.
2. Format version `u32`, currently 1.
3. Checkpoint sequence `u64`.
4. Logical `containerSize`, `blockCount`, and `nextNodeId`, each `u64`.
5. Label as a `u32` UTF-8 byte length followed by its bytes (at most 128 bytes).
6. Key-slot mask `u32`.
7. Metadata image byte length `u64`.
8. Metadata-page run count `u64`, then that many pairs of `first physical block u64` and
   `block count u64`.
9. Authenticated `physicalSize u64`.

Each metadata page is a normal encrypted block record of kind 5. Concatenated plaintext pages,
trimmed to `metadataSize`, form one metadata image:

1. Node count `u64`.
2. That many node records, each containing `id u64`, `parentId u64`, a sized UTF-8 name, file
   attributes `u32`, size `u64`, four timestamps (`creation`, `last access`, `last write`,
   `change`) as `u64` 100-nanosecond ticks since 1601-01-01 UTC, security-data byte count `u32`
   and opaque bytes, then block-run count `u64` and that many `(logical start, physical start,
   count)` `u64` triples.

Names and labels use the same sized-string encoding: a little-endian `u32` byte count followed by
that many bytes, canonically UTF-8. The current reader bounds the count but does not validate
UTF-8. The root node has identifier 1, empty name, and itself as parent.
The free-block map is not stored; it is rebuilt as the complement of metadata pages and file
blocks. Node names are indexed after Unicode simple lowercase mapping without normalization.
Production readers cap the node count at 100,000,000, names at 4 KiB, labels at 128 bytes, and
security data at 1 MiB.
Each node's run count cannot exceed the block count. Physical run ranges must fit the block count,
and physical blocks cannot be shared by nodes or metadata pages. Logical runs must be ordered and
non-overlapping, but the current reader does not require them to fit the node's declared file size.

Version-1 writers end the header and metadata image after their final listed field. The current
reader does not explicitly reject authenticated trailing bytes in either stream. The header's
key-slot mask is read from the encrypted header but its upper bits are not separately validated.

## Journal

The journal is a circular array of 256 fixed 4,096-byte slots. A checkpoint sequence is shared
with journal records. A journal record's associated-data identifier is `sequence % 256`, and its
plaintext begins with:

1. Sequence `u64` and next node identifier `u64`.
2. Sized label.
3. Removed-node count `u64`, followed by node identifiers `u64`.
4. Upserted-node count `u64`, followed by full node records as above.
5. Metadata-patch count `u64`, followed by patches containing `id u64`, `parentId u64`, sized
   name, attributes `u32`, and the same four `u64` timestamps.

For compatibility, a journal record ending after the full-node list is accepted as an older
version that has no metadata-patch section. A mutation normally appends one journal record. A
checkpoint writes the full metadata image into fresh pages, then writes the next sequence into the
header slot that is not currently active. Only after that header is durable can the previous
checkpoint's pages be reused. Closing a changed writable volume checkpoints it. A full journal or
a change too large for one journal slot also causes a checkpoint. The current decoder bounds the
removed-node, upserted-node, and metadata-patch counts at 100,000,000 before allocating them.

Recovery starts at `checkpoint sequence + 1` and reads only consecutive expected ring slots. It
stops at the first absent, unauthenticated, undecodable, or out-of-sequence record. The journal
sequence is not anchored outside the container; restoring an older complete copy can therefore
restore an older valid state. The current decoder accepts older journal records that end after the
full-node upsert list; it does not require end-of-stream after every parsed record. If a decoded
record fails while being applied semantically, recovery fails instead of skipping it.

## Opening and validation

For a normal container, Windows opening rejects files marked sparse by the host and opens the file
with the requested access. The Linux backend does not currently detect sparse files. Both
platforms check the minimum size and try the four wrapped-key slots using the shared salt. If no
outer slot opens, the optional hidden-locator extension may identify a bounded hidden view and the
credential is tried against that view's key slots.

After deriving the record keys, the reader checks both header slots. A slot is usable only if its
locator, decoded length, AEAD tag, magic, and version validate. Of two usable headers, the greater
sequence is selected (slot 0 wins a tie). This selection precedes full restore; if restoring the
newer usable header fails, the current reader reports `PasswordOrDamaged` and does not retry the
older slot. The selected header is checked against the host length: logical size, block count,
metadata-page count and runs, and physical size must fit the view. Every metadata page is
authenticated before the image is parsed. Node counts, string lengths, security sizes, block-run
counts and block ranges are bounded before they drive allocations. The page-run list must describe
exactly `ceil(metadataSize / 4,096)` pages; runs cannot be empty and must fit within `blockCount`.

After journal replay, recovery requires exactly one root identifier to resolve as a directory
whose parent is itself, every other node's parent to be a directory, and `nextNodeId` to exceed
all stored node identifiers. It rebuilds block ownership and rejects out-of-range or overlapping
metadata and data blocks.

If a protection password is supplied for an ordinary outer volume, the hidden extension is
located after outer unlock. Once restore has rebuilt the free extents, the entire protected range
must still lie inside a genuinely free outer extent. Opening a hidden view and requesting outer
protection at the same time is rejected.

During opening, wrong passwords, unusable headers, unsupported versions, and failures while
authenticating or validating the header, metadata image, or replayed journal report the same
`PasswordOrDamaged` result. A later data-block authentication failure reports `Corrupted`.
Optional hidden-range protection validation can report `HiddenProtected`; invalid combinations of
an inner-volume password and an outer-protection password report `InvalidInput`. Host-level I/O
errors and (on Windows) sparse-file rejection can also be distinguished. This error behavior does
not prevent rollback to an older complete container copy and does not replace an independent
cryptographic audit.
