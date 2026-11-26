# Extended OpenSSL 4.1 comparison

Swag `b281647e48` was compiled natively in Release with compiler and runtime `44e09064f1` on Linux x86-64. The full profiles used CPU 0 on an AMD EPYC 9V74. System OpenSSL 3.5.7 and upstream OpenSSL 4.1.0 used the same C EVP driver for each suite.

Every measured digest or tag matched across all three engines for all 42 profiles. The backing input, key and customization arrays use `(37i + 11) & 255`, `(19i + 3) & 255` and `(13i + 15) & 255` at index `i`. Each slice starts at index 1. Each result is the median of 15 per-thread CPU samples, with five measurements per engine in each of three rotated orders. Each sample hashes approximately 4 MiB or reaches its configured call limit. The reference allocates the EVP context and configures digest and MAC parameters before the timer. Every MAC operation initializes the raw key again.

The 64 B table uses a dedicated repeat on CPU 3. The largest between-batch median spread in that repeat was 24% in a KMACXOF profile. Both CPU groups gave the same direction of change for the two empty-customization profiles.

| Algorithm | Profile | Input | Swag µs | OpenSSL 3.5.7 µs | OpenSSL 4.1.0 µs | Swag speed / fastest EVP |
|---|---|---:|---:|---:|---:|---:|
| HMAC-SHA3-256 | 32 B key, 1 update | 64 B | 24256 | 21288 | 20947 | 0.864× |
| HMAC-SHA3-256 | 136 B key, 1 update | 64 B | 25941 | 21455 | 21487 | 0.827× |
| HMAC-SHA3-256 | 256 B key, 1 update | 64 B | 35502 | 31632 | 30960 | 0.872× |
| HMAC-SHA3-256 | 32 B key, 2 updates | 64 B | 24978 | 21421 | 20767 | 0.831× |
| HMAC-SHA3-256 | 136 B key, 2 updates | 64 B | 25070 | 21497 | 20868 | 0.832× |
| HMAC-SHA3-256 | 256 B key, 2 updates | 64 B | 35533 | 31599 | 30669 | 0.863× |
| KMACXOF128 | 0 B customization, 200 B output | 64 B | 17517 | 20106 | 20608 | 1.148× |
| KMACXOF128 | 12 B customization, 200 B output | 64 B | 22347 | 19882 | 20138 | 0.890× |
| KMACXOF256 | 0 B customization, 200 B output | 64 B | 17151 | 19887 | 19953 | 1.160× |
| KMACXOF256 | 12 B customization, 200 B output | 64 B | 22646 | 19740 | 20049 | 0.872× |
| SHA-512/224 | 1 update | 64 B | 9768 | 7932 | 7309 | 0.748× |
| SHA-512/224 | 2 updates | 64 B | 9823 | 8124 | 7482 | 0.762× |
| SHA-512/256 | 1 update | 64 B | 9859 | 7928 | 7236 | 0.734× |
| SHA-512/256 | 2 updates | 64 B | 9708 | 8087 | 7419 | 0.764× |

The 1 MiB profiles used four operations per sample.

| Suite | Swag speed / fastest EVP at 1 MiB |
|---|---:|
| HMAC-SHA3-256 | 0.895–0.901× |
| KMACXOF128/256 | 0.889–0.929× |
| SHA-512/224 and SHA-512/256 | 0.737–0.784× |

[HMAC-SHA3 raw timings and tags](hmac-sha3-openssl-4.1.json) · [KMACXOF raw timings and tags](kmac-xof-openssl-4.1.json) · [SHA-512/t raw timings and digests](sha512-t-openssl-4.1.json)

[HMAC-SHA3 64 B repeat](hmac-sha3-openssl-4.1-short.json) · [KMACXOF 64 B repeat](kmac-xof-openssl-4.1-short.json) · [SHA-512/t 64 B repeat](sha512-t-openssl-4.1-short.json)
