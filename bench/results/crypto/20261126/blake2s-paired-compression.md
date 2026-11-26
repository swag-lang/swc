# BLAKE2s compression interleave and round schedule

The candidate advances two independent G functions at a time and reads the message words directly on little-endian targets. The current round's schedule pointer is computed once, so each message index is loaded at a fixed offset. The Release benchmark executable's `.text` shrinks by 128 bytes.

## Method

The BLAKE2s baseline is `51fc17f2fe4c6e506cc40605d4f79dad28a042d1`. Both Swag arms use the same Release compiler and runtime from `44e09064f1cef5af4258c0decaeb670e38053378`. References are libb2 0.98.1 and the OpenSSL 4.1.0 default provider, using BLAKE2S-256 and BLAKE2SMAC. OpenSSL reuses its context allocation and initializes it in each timed operation.

The benchmark uses 32-byte digests on inputs of 16, 32, 64, 1024, 65536 and 1048576 bytes. It times one-shot calls and two streaming updates split in half. Each benchmark runs with no key or a 32-byte key. Input starts one byte into storage, where byte `i` is `(37*i + 11) & 255`. Key byte `i` is `(19*i + 3) & 255`. Each batch runs `min(16000, 4194304 / input_bytes)` operations and compares the complete digest against Python hashlib.

Timing uses `CLOCK_THREAD_CPUTIME_ID` pinned to CPU 3 on Linux x86-64 and an AMD EPYC 9V74. Five rotations shift the order of all five implementations. Each rotation contributes five batches per profile and implementation. Results show median microseconds per batch. The rotation interval brackets the smallest and largest speedup from the median of five batches in each rotation. [Raw samples](blake2s-paired-compression-cpu3.json)

| Key bytes | Input mode | Input bytes | Previous Swag | Current Swag | libb2 | OpenSSL 4.1 | Swag speedup [rotation interval] |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | one-shot | 64 | 4299 | 3802 | 2215 | 2657 | 1.131× [1.085, 1.344] |
| 0 | one-shot | 1048576 | 11413 | 10109 | 7926 | 6916 | 1.129× [1.106, 1.263] |
| 0 | two updates | 64 | 4878 | 4510 | 2221 | 2693 | 1.082× [1.071, 1.194] |
| 0 | two updates | 1048576 | 11475 | 10073 | 7929 | 6913 | 1.139× [1.110, 2.236] |
| 32 | one-shot | 64 | 7229 | 6375 | 4292 | 4539 | 1.134× [1.112, 1.266] |
| 32 | one-shot | 1048576 | 11480 | 10063 | 7894 | 6898 | 1.141× [1.095, 1.326] |
| 32 | two updates | 64 | 7828 | 7145 | 4319 | 4578 | 1.096× [0.911, 1.191] |
| 32 | two updates | 1048576 | 11692 | 10016 | 7936 | 6927 | 1.167× [1.131, 1.259] |

Across all 24 profiles the candidate's median CPU speedup is 1.082–1.167×. OpenSSL remains 1.45–1.46× faster at 1 MiB, and libb2 leads the 64-byte rows. Some rotation intervals were wide under concurrent jobs, especially for unkeyed two-update 1 MiB and keyed two-update 64 bytes.

The additional direct one-shot final-block variant matched all 896 independent digests. It improved the 16-byte one-shot rows and the 32-byte keyed one-shot row relative to the compression-only candidate, while the compression-only candidate led most remaining profiles. Both arms are in the raw table.

## Validation

Four focused Core BLAKE2s cases passed in each of native Release, native Release-safe and JIT. The selected candidate passed a further 896 Python hashlib comparisons across four digest lengths, four key sizes, 14 payload lengths and four update profiles. These checks include empty and one-byte input, the 63–65 byte boundary, and unaligned storage.
