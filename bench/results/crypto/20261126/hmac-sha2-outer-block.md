# HMAC-SHA-224 and SHA-256 direct outer blocks

The inner SHA hash finalizes in its context. Its state words go directly
into the outer context’s final block in big-endian order, followed by
the fixed one-block padding. The HMAC exports the completed outer digest
and securely clears both contexts. The public SHA digest routines share
the same inner finalization logic.

Both native Release builds used compiler `44e09064f1` and standard-library
baseline `da13763b7b`. Seventeen paired rounds ran on CPU 2 of an AMD
EPYC 9V74 under Linux 6.18.57. Each timed HMAC used a fresh 32-byte
key setup and checked the full tag against OpenSSL 4.1.0, OpenSSL
3.5.9 and Nettle 3.10.1. The tables show median process CPU
nanoseconds and paired 95% time ratios.

| HMAC | Bytes | Before | Direct | OpenSSL 4.1.0 | Nettle | Direct / before | Direct / Nettle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 16 | 217.6 | 188.8 | 242.9 | 195.2 | 0.869 [0.846, 0.966] | 0.966 [0.947, 1.075] |
| SHA-224 | 32 | 218.3 | 186.8 | 238.9 | 197.5 | 0.874 [0.835, 0.917] | 0.951 [0.934, 1.015] |
| SHA-224 | 55 | 219.8 | 184.7 | 235.4 | 196.0 | 0.849 [0.832, 0.880] | 0.944 [0.936, 1.007] |
| SHA-224 | 56 | 257.2 | 226.3 | 278.5 | 237.2 | 0.880 [0.857, 0.954] | 0.951 [0.932, 1.021] |
| SHA-224 | 128 | 294.0 | 253.1 | 318.4 | 269.3 | 0.883 [0.830, 0.943] | 0.943 [0.936, 0.986] |
| SHA-224 | 4096 | 2551.6 | 2530.6 | 2586.2 | 2525.8 | 0.998 [0.988, 1.007] | 1.010 [0.990, 1.026] |
| SHA-256 | 16 | 231.5 | 209.9 | 240.8 | 200.6 | 0.907 [0.878, 0.913] | 1.035 [1.030, 1.063] |
| SHA-256 | 32 | 228.6 | 207.0 | 235.5 | 198.1 | 0.903 [0.875, 0.931] | 1.047 [1.036, 1.052] |
| SHA-256 | 55 | 228.2 | 206.8 | 232.7 | 198.4 | 0.911 [0.887, 0.927] | 1.043 [1.024, 1.052] |
| SHA-256 | 56 | 267.7 | 248.3 | 282.3 | 243.1 | 0.925 [0.912, 0.949] | 1.025 [0.992, 1.061] |
| SHA-256 | 128 | 289.8 | 303.5 | 318.4 | 273.3 | 0.951 [0.917, 1.079] | 1.009 [0.989, 1.136] |
| SHA-256 | 4096 | 2573.2 | 2534.3 | 2579.8 | 2508.7 | 0.985 [0.953, 0.999] | 1.002 [0.982, 1.017] |

Swag used 12–15% less CPU for SHA-224 at 16–128 bytes and
7.5–9.7% less for SHA-256 at 16–56 bytes. It used less CPU than
OpenSSL 4.1.0 in all twelve profiles. Against Nettle, Swag used
5.7% less CPU for SHA-224 at 128 bytes. The other SHA-224
intervals included parity. Nettle used less CPU for SHA-256 at
16–55 bytes, and the larger SHA-256 intervals included parity.

## Consumers and standard SHA

| HKDF | Digest blocks | Before | Direct | Direct / before |
| --- | ---: | ---: | ---: | ---: |
| SHA-224 | 1 | 524.7 | 454.6 | 0.842 [0.795, 0.892] |
| SHA-224 | 4 | 1118.1 | 966.3 | 0.878 [0.810, 0.962] |
| SHA-224 | 32 | 6648.3 | 5458.5 | 0.828 [0.713, 0.893] |
| SHA-224 | 255 | 49289.9 | 41387.0 | 0.836 [0.739, 0.858] |
| SHA-256 | 1 | 503.8 | 466.9 | 0.921 [0.821, 1.129] |
| SHA-256 | 4 | 1058.4 | 961.8 | 0.908 [0.846, 0.927] |
| SHA-256 | 32 | 5748.3 | 5095.3 | 0.887 [0.879, 0.901] |
| SHA-256 | 255 | 43142.0 | 37854.3 | 0.876 [0.871, 0.934] |

HKDF-SHA-224 used 12–17% less CPU. HKDF-SHA-256 used 9–12%
less for 4–255 blocks. The one-block SHA-256 interval included
parity. All ten plain SHA-224 and SHA-256 controls across 16 bytes
to 1 MiB and the two deterministic P-256 signing controls also
included parity.

The differential sweep checked 216 HMAC and 72 plain SHA profiles,
including empty and unaligned inputs and HMAC keys of 0, 32 and 131
bytes. Native Release and QEMU with SHA-NI disabled produced identical
bytes to both OpenSSL builds and to Nettle for HMAC. The 32 focused
Core tests passed in native Release, Release-safe and Release JIT.

Build the common C reference with `-DSWAG_BENCH_HMAC_NETTLE` and
`$(pkg-config --cflags --libs nettle)`. Pass
`--hmac-nettle-reference --algorithm hmac-sha224 --algorithm hmac-sha256`
to the runner. The Nettle reference calls the SHA-224 or SHA-256
HMAC key-setup, update and digest routines inside the timer.

[Reproduction commands](../../../workloads/crypto/README.md) · [Previous key-pad campaign](hmac-sha224-sha256.md) · [Raw times](hmac-sha2-outer-block.json)
