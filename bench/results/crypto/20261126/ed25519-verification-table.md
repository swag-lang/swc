# Reusable Ed25519 verification table

Verification builds one public-key table for the subgroup and challenge
calculations. The public group-order digits select directly from the table.
The formulas defer the extended coordinate until an operation needs it.
The regression fixture checks rejection of a low-order public key.

The native Release timing used CPU 1 and the process clock with a single
worker and one valid signature over a fixed 40-byte message. It collected
15 batches of 96 calls for each Swag build. The library comparison used
11 batches of 512 calls per reference, with the identical public key,
message and signature.

| Implementation | Median process CPU µs per verification |
| --- | ---: |
| Swag before | 293.57 |
| Swag reused table | 244.16 |
| OpenSSL 3.5.7 | 106.95 |
| libsodium 1.0.18 | 52.10 |

Ten focused tests passed in each native Release configuration. Another
24 independent cases matched OpenSSL.

[Raw Swag samples](ed25519-verification-table.json) · [Raw reference samples](ed25519-verification-table-references.log).
