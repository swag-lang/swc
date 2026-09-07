# Hidden volumes

## Workflow and capacity

Create an ordinary container first and put its ordinary files in it. In **Open**, select that
container and enter its outer password and key files. **Create hidden volume** asks for a separate
password, confirmation, optional ordered key files, hidden capacity, and minimum space to leave
for ordinary files. The latter defaults to 256 MiB in the interface. The largest suitable free
extent is used, with the hidden volume at its high end. Creation refuses insufficient contiguous
space or an insufficient outer reserve; it never fills all free space automatically. At least
16 outer blocks remain free even when a direct caller requests a smaller reserve.

Both capacities include their own format overhead. The reserve is ordinary plaintext file
capacity; the hidden range consumes physical encrypted records. The creation limit is calculated
with those different units, rounding the hidden byte range up to outer records. The reserve is
not an allocation, flag, reduced capacity, or hidden-volume entry in the outer filesystem.

Mount the same container with the hidden credentials to open the hidden filesystem. With the
outer credentials, it opens the ordinary filesystem. Ordered key files are combined with each
password through the existing `VaultAccess` derivation; neither their paths nor the credentials
are saved in the container. Hidden credentials must be nonempty and distinct from every outer
credential. Changing either password must preserve this distinction.

## Optional protection

**Protect the hidden volume when writing** is off by default. With it off, an ordinary mount
behaves exactly as before: all its free space remains available, and adding enough ordinary data
can overwrite the hidden volume. A read-only mount cannot overwrite either volume.

Enabling protection asks for the hidden password and key files for that mount. The checkbox resets
after the mount request; it must be selected again for the next manual mount. The hidden
locator must authenticate and its entire range must still be free in the outer filesystem;
otherwise mounting fails. Protection does not mount the hidden filesystem, remove blocks from
the outer allocator, or reduce the free capacity Windows sees. Successful protected mounting is
reported on the status line. If startup mounting is explicitly saved with privacy mode off, the
protection choice is retained and hidden access is requested again; access material is never saved.

Every data, metadata, journal, and password-slot write passes through a bounded storage view.
A nonempty transfer intersecting the protected half-open byte interval is rejected before host
I/O. After the first collision, all subsequent writes are rejected until unmount, including
checkpoint writes during close. WinFsp reports media write protection. No record of the collision
or protected range is written to the outer filesystem.

Hidden views cannot grow, shrink, or refresh camouflage. These operations are also disabled on
a protected outer view. An unprotected outer volume retains its ordinary resize behavior and can
therefore destroy hidden data by shrinking. Unmounting releases protection; opening the host
with an older Swag Vault binary is unsafe because old password-slot writers replace locator padding.

## Version-1 format extension

The existing outer geometry, format version, KDF cost, ciphertext suite, and metadata encoding
are unchanged. All new containers continue to randomize their complete physical file. Hidden
creation does not change its host's length or record the hidden range in outer metadata.

Each of the four 256-byte key slots has a 32-byte random prefix and a 92-byte authenticated
key payload. Its last 128 bytes, at absolute offsets `128 + index * 256`, are now reserved for
an optional hidden locator. Ordinary key-slot creation, rotation, and erasure write only the
92-byte payload and preserve the trailing padding, whether or not a hidden volume exists.
No marker says whether a locator is present.

| Bytes within a locator | Contents |
| --- | --- |
| 0-31 | Independent random Argon2id salt |
| 32-43 | Random ChaCha20-Poly1305 nonce |
| 44-59 | Encrypted 16-byte geometry |
| 60-75 | Authentication tag |
| 76-127 | Random padding |

The locator key uses the normal production Argon2id parameters: 256 MiB, three iterations,
four lanes, and a 32-byte result. Associated data is the existing 12-byte little-endian
`Crypto.associatedData` encoding with record kind **9** and the locator index. Geometry holds
two little-endian u64 values: the absolute hidden base and the exact bounded byte length.
Authentication precedes decoding. The decoder checks minimum geometry and overflow-safe host
bounds before following the base. The hidden volume then uses its own random 64-byte master
key, salt, key slots, two headers, journal, metadata pages, and data blocks with the existing
version-1 encoding. Its record coordinates are relative to its bounded view. It has no extra
camouflage tail; its authenticated physical length equals the hidden range length.

Opening tries the outer slots first. If they do not authenticate, it tries the hidden locators,
then independently unlocks and validates the indicated hidden filesystem. Without protection,
outer opening never scans locators. A missing locator, wrong hidden credential, unsupported
header, or damaged hidden authentication record reports the usual password-or-damaged failure.

One container holds one hidden filesystem, with up to four access slots. A locator at index `i`
is published only after hidden key slot `i` is durable. During initial creation, the entire
hidden range is randomized, a root checkpoint is flushed, old locators are erased, and the new
key slot and locator are published last. Password rotation writes and verifies the replacement
before erasing old access, just as on an ordinary volume. Creating another hidden volume
explicitly replaces the previous hidden access and can overwrite its data. Cancellation during
replacement can damage the previous hidden volume, but never allocates or modifies ordinary files.

## Limits and review

This is the Swag Vault format, not an implementation of the VeraCrypt file format. Its workflow
follows VeraCrypt's optional hidden-volume protection and apparent free-space behavior:
[hidden volumes](https://veracrypt.io/en/Hidden%20Volume.html) and
[protection](https://veracrypt.io/en/Protection%20of%20Hidden%20Volumes.html).

The intended passive observer sees random-looking bytes without an outer metadata flag identifying
a hidden filesystem. This is not a guarantee against a compromised host, captured memory or
credentials, Windows/application traces, backups, snapshots taken at different times, or forensic
comparison of writes. An observer of a protected mount can detect refused writes. Existing
format and external-audit backlog items remain applicable; this extension has no independent
cryptographic audit and does not establish equivalence to VeraCrypt's security assurances.

## Copy harness

The explicit `vault.hidden-copy` application tag builds a console harness that copies an existing
Swag Vault filesystem into a new hidden volume. Run it through the normal application tool:

```text
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm run swagvault --tag vault.hidden-copy --num-cores 6
```

Its child environment supplies `SWAG_VAULT_COPY_SOURCE`, `SWAG_VAULT_COPY_TARGET`,
`SWAG_VAULT_COPY_PASSWORD` (source and new outer access), and `SWAG_VAULT_COPY_HIDDEN_PASSWORD`.
Use a fresh destination: creation never replaces an existing host file. It retains the source's
capacity for the hidden filesystem and adds 1 GiB for ordinary files. It opens the source read
only, streams files directly between encrypted volumes, preserves per-entry metadata and security,
reopens the hidden volume, and compares every copied byte. It then writes an ordinary file with
protection enabled and compares the hidden files again. No plaintext extraction directory is used.
A stopped copy leaves its new destination for inspection; the source remains untouched.

Build the ordinary application without the tag when finished.
