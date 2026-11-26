# MD5 round arithmetic comparison

The comparison used the MD5 compression path from `63f5e2484a` as its Swag control and upstream OpenSSL 4.1.0 EVP as its external reference. All full 16-byte digests matched the reference across one-shot and two-update profiles. The AMD EPYC 9V74 runs used native Swag Release with compiler and runtime `52a1ec78e9`. Each sample measured per-thread CPU time for up to 32,000 hashes or about 4 MiB. Each input slice began at a one-byte offset.

The fourth-round candidate used the complement of the original Boolean expression and folded its addition into a subtraction and an adjusted round constant. The first and second round candidate used XOR-based selection expressions with the same truth tables. The isolated CPU 3 comparison collected 15 samples per arm.

| Profile | Control µs | Fourth-round complement µs | First and second round XOR µs | OpenSSL 4.1.0 µs |
|---|---:|---:|---:|---:|
| One-shot, 16 B | 3294 | 3338 | 3448 | 3279 |
| One-shot, 55 B | 3052 | 3072 | 3169 | 2995 |
| One-shot, 1 MiB | 5937 | 5912 | 6158 | 5316 |
| Two updates, 64 B | 6536 | 6253 | 6487 | 5948 |
| Two updates, 1 MiB | 6204 | 5889 | 6093 | 5250 |

For the 1 MiB two-update profile, individual run medians ranged from 5,868 to 6,386 µs for the control and 5,866 to 6,070 µs for the fourth-round candidate. The one-shot profiles showed changes of small magnitude. Grouping the message word and round constant before adding them to the evolving state regressed throughput by about 15% in the initial CPU 0 screen at 64 KiB and 1 MiB.

[Isolated CPU 3 timings and digests](md5-round-arithmetic-cpu3.json) · [Initial CPU 0 screen](md5-round-arithmetic-screen.json)
