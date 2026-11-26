# RSA Montgomery setup by exponentiating the limb count

Setup computes the Montgomery representation of `2^64` in 64 modular
doublings, then raises it to the limb count in the same domain. This
produces `R² mod n`. The exponent is determined by the public key width.
An independent integer model checked every supported limb count from
32 to 64. The fixed-window schedule for the private exponent stays in
place.

Fifteen paired native Release trials used process CPU time on AMD
EPYC 9V74 CPU 4. The baseline is `690ddf12b0`. OpenSSL 4.1.0 uses
prepared operation contexts. Swag's raw-key calls include their key
setup, which explains why the change primarily benefits PSS verification.

| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| rsa-pss-verify | 2048 | square | 3540 | 5.713e+04 | — | — |
| rsa-pss-verify | 2048 | r2-power | 1.358e+04 | 5.713e+04 | — | 3.81 [3.65, 3.93] |
| rsa-oaep-decrypt | 2048 | square | 161.8 | 3889 | 497 | — |
| rsa-oaep-decrypt | 2048 | r2-power | 166.1 | 3889 | 497 | 1.02 [0.98, 1.05] |
| rsa-pss-verify | 2080 | square | 3217 | 2.833e+04 | — | — |
| rsa-pss-verify | 2080 | r2-power | 1.161e+04 | 2.833e+04 | — | 3.61 [3.56, 3.65] |
| rsa-oaep-decrypt | 2080 | square | 152 | 784.6 | 235.6 | — |
| rsa-oaep-decrypt | 2080 | r2-power | 156 | 784.6 | 235.6 | 1.03 [1.01, 1.04] |
| rsa-pss-verify | 3072 | square | 1701 | 2.706e+04 | — | — |
| rsa-pss-verify | 3072 | r2-power | 6264 | 2.706e+04 | — | 3.68 [3.61, 3.73] |
| rsa-oaep-decrypt | 3072 | square | 51.65 | 1364 | 152.2 | — |
| rsa-oaep-decrypt | 3072 | r2-power | 51.91 | 1364 | 152.2 | 1.01 [0.995, 1.01] |
| rsa-pss-verify | 4096 | square | 978.6 | 1.533e+04 | — | — |
| rsa-pss-verify | 4096 | r2-power | 3614 | 1.533e+04 | — | 3.7 [3.62, 3.78] |
| rsa-oaep-decrypt | 4096 | square | 22.09 | 651.7 | 64.86 | — |
| rsa-oaep-decrypt | 4096 | r2-power | 22.2 | 651.7 | 64.86 | 1.01 [0.998, 1.04] |

Every timed result matched. The 72-case verifier used six independently
checked key fixtures at offsets 0, 1 and 7 across all four RSA operations.
Five focused Core tests passed in JIT and native Release and Release-safe.

[Raw timings](rsa-montgomery-setup-power.json) · [Differential results](rsa-montgomery-setup-power-verification.json) · [Reproduction](../../../workloads/rsa/README.md)
