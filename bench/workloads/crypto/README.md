# Swag Core cryptography and checksum comparison

The workload compares native Release Swag Core calls with byte-equivalent public library
calls. It measures one-shot digest, checksum, MAC, stream encryption and authenticated
encryption. Each implementation uses the same deterministic input, CPU affinity and
synthetic key, nonce and associated data when applicable. The default is one worker
and one Linux CPU.
Whole ciphertext and tags are checked. Checksums use little-endian bytes and digests use
the standard byte order.

The clock covers repeated operations on one in-memory message, including per-message
initialization and finalization. Allocation, library/provider selection, input and output
I/O, a warm-up call and output comparison sit outside it. OpenSSL context containers are
reused, and ciphers still receive the key and nonce per message. The harness calibrates a
fixed number of iterations per implementation, shuffles their order in each round and
verifies output in every sample. The JSON records wall and process CPU time. The table
uses process CPU time by default. Run with `--clock wall` to measure elapsed time,
including waits for CPU scheduling. Confidence intervals use the shared
distribution-free paired median estimator when enough samples are available. With multiple library versions
of the same operation the Markdown table uses the fastest median at that size. The JSON
retains all trials, library results, execution order and output fingerprints.

## Linux x86-64

Set `WORK` to an absolute scratch directory outside the checkout, `SWC` to the Release Swag
compiler with its adjacent runtime, and `REPO` to this checkout. Install a C compiler,
CMake, NASM, OpenSSL and zlib development headers, and liblzma.

```sh
git clone --depth 1 --branch v1.26 https://github.com/ebiggers/libdeflate.git "$WORK/libdeflate"
git clone --depth 1 --branch v2.32.1 https://github.com/intel/isa-l.git "$WORK/isa-l"
git clone --depth 1 --branch 1.8.7 https://github.com/BLAKE3-team/BLAKE3.git "$WORK/blake3"
cmake -S "$WORK/isa-l" -B "$WORK/isal-build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/isal-build" --target isal

cc -O3 -shared -fPIC -I"$WORK/libdeflate" \
  "$WORK/libdeflate/lib/adler32.c" "$WORK/libdeflate/lib/crc32.c" \
  "$WORK/libdeflate/lib/x86/cpu_features.c" -o "$WORK/libdeflate.so"

cc -O3 -shared -fPIC -I"$WORK/blake3/c" \
  "$WORK/blake3/c/blake3.c" "$WORK/blake3/c/blake3_dispatch.c" \
  "$WORK/blake3/c/blake3_portable.c" "$WORK/blake3/c/blake3_sse2_x86-64_unix.S" \
  "$WORK/blake3/c/blake3_sse41_x86-64_unix.S" "$WORK/blake3/c/blake3_avx2_x86-64_unix.S" \
  "$WORK/blake3/c/blake3_avx512_x86-64_unix.S" -o "$WORK/libblake3.so"

cc -O3 -Wall -Wextra -Werror -I"$WORK/blake3/c" -I"$WORK/isa-l/include" \
  -I"$WORK/libdeflate" "$REPO/bench/workloads/crypto/reference.c" \
  -L"$WORK" -L"$WORK/isal-build" -Wl,-rpath,"$WORK:$WORK/isal-build" \
  -lblake3 -lisal -ldeflate -lcrypto -lz -l:liblzma.so.5 -o "$WORK/reference"

mkdir -p "$WORK/std-snapshot"
git -C "$REPO" archive HEAD bin/std | tar -x -C "$WORK/std-snapshot"
cd "$WORK"
SWAG_PATH="$WORK/std-snapshot/bin" "$SWC" build -d "$REPO/bench/workloads/crypto/src" \
  --module-file "$REPO/bench/workloads/crypto/module.swg" -bc release \
  --artifact-kind executable --artifact-name swag-crypto \
  --out-dir "$WORK/swag-bin" --work-dir "$WORK/swag-work"

python3 -B "$REPO/bench/workloads/crypto/run.py" \
  --swag "candidate=$WORK/swag-bin/swag-crypto" --reference "$WORK/reference" \
  --cpu 0 --scratch "$WORK" --output "$WORK/results.json" --markdown "$WORK/results.md"
```

Repeat `--swag LABEL=PATH` to pair before and after builds in one campaign. Build each
against its own standard-library snapshot and output directories. The first build
is the baseline. Repeat `--algorithm` and `--size` to select a subset. `--verify-only` skips
timings and can be combined with `--offset 1` to check unaligned input.

Select HMAC with `--algorithm hmac-sha384` or `--algorithm hmac-sha512`. The
one-shot operations use a deterministic 32-byte key. Include `--size 111 --size 112`
to compare the payloads on either side of the SHA-384/512 padding boundary.

## Worker scaling

Repeat `--cpu` to set a common affinity mask for every build and reference. Give each Swag
label a worker count with `--workers LABEL=COUNT`. Omitted counts default to one, and
references run with the one-worker setting. Wall time measures parallel throughput.
Process CPU time adds the work done by all the threads. The JSON keeps both clocks and
records the CPU affinity and worker counts.

```sh
python3 -B "$REPO/bench/workloads/crypto/run.py" \
  --swag "serial=$WORK/swag-bin/swag-crypto" --swag "parallel=$WORK/swag-bin/swag-crypto" \
  --workers parallel=4 --cpu 0 --cpu 1 --cpu 2 --cpu 3 --clock wall \
  --reference "$WORK/reference" --algorithm crc64-ecma --size 4194304 --size 16777216 \
  --scratch "$WORK" --output "$WORK/worker-scaling.json" --markdown "$WORK/worker-scaling.md"
```

## Public-key operations

The public-key operations are selected individually with `--algorithm x25519-public`,
`x25519-shared`, `ed25519-public`, `ed25519-sign`, `p256-public` and `p256-sign`. Fixed-size key inputs
are 32 bytes. Signing defaults to 64-byte and 4 KiB messages. Public-key rows
report operations per second. OpenSSL receives a raw key or seed on each call, just
as Swag does. The P-256 comparator uses OpenSSL's fixed-base EC multiplication with
the group and scratch containers allocated before timing. P-256 signing enables
RFC 6979 nonces in OpenSSL and exports the two 32-byte signature components.

[Recorded comparison](../../results/crypto/20261126/README.md).
