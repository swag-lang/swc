# Signed P-256 generator comb

The fixed-base multiplier uses eight stripes of signed four-bit columns.
Each stripe indexes eight public table entries by scanning all of them with
masks. An additional sign mask negates the selected Y coordinate in place.
Every stripe adds a finite point, and the accumulator takes eight scheduled
doubling steps. The previous unsigned comb used sixteen steps and masked
away the addition for its zero digit. The new table holds 64 points (4,096
bytes) versus 60 (3,840 bytes).

For a scalar `k` and group order `n`, the recoding takes
`a = ((k + 2^256 − 1) / 2) mod n`. Here division is multiplication by the
inverse of two modulo `n`. Interpreting bit `i` of `a` as the sign of
`2^i` reconstructs `k` modulo `n`. The top sign of each four-column group
chooses whether the table point is negated. An independent integer model
checked 4,101 scalars, and the native multiplier clears the recoded scalar
and selected point as it runs. Arbitrary-point multiplication is unchanged.

Nineteen paired native Release process CPU-time trials ran on CPU 4 of the
AMD EPYC 9V74. The prior unsigned comb is `6f931af0ec`. System OpenSSL
3.5.7 provides the deterministic signing comparison. OpenSSL 4.1.0 also
runs for public-key generation and verification.

| Profile | Unsigned ops/s | Signed ops/s | Fastest reference ops/s | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| Public key | 11,100 | 12,400 | 94,100 | 1.11 [1.09, 1.17] |
| Sign 64 B | 9,000 | 9,670 | 33,300 | 1.08 [1.07, 1.08] |
| Sign 4 KiB | 8,710 | 9,370 | 30,600 | 1.07 [1.07, 1.08] |
| Verify 64 B | 2,910 | 2,980 | 14,700 | 1.02 [0.997, 1.02] |
| Verify 4 KiB | 2,880 | 2,930 | 14,100 | 1.02 [1.01, 1.04] |

The separate four- and eight-stripe screen checked all five profiles. A
29-pair repeat confirmed the eight-stripe public-key improvement before the
in-place Y selection. The final byte-exact sweep matched OpenSSL 4.1.0 for
326 public keys and 39 deterministic signatures. Public-key inputs cover
every single-bit scalar, values near the order, and deterministic random
scalars. The seven focused P-256 tests passed in native and JIT execution in
Release and Release-safe.

[Final paired trials](p256-signed-comb.json) · [Stripe count screen](p256-signed-comb-screen.json) · [Public-key repeat](p256-signed-comb-repeat.json) · [Exact reference cases](p256-signed-comb-verification.json)
