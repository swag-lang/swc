# BLAKE3 worker scaling

The one-shot and streaming measurements use the same deterministic in-memory
fixture, worker counts and Linux CPU affinity. The outputs are validated
against BLAKE3 C 1.8.7. The C driver calls its single-worker API and reports the
SIMD dispatch width. Swag starts the configured pool before warming the
operation. The timer covers hashing through finalization, including the
scheduling work performed by each call.

Streaming starts a fresh hash for each message and passes its bytes to
`update` in fixed 4 KiB, 64 KiB or 1 MiB slices. The last slice holds the count
of bytes remaining.

## Build and run on Linux x86-64

Set `REPO` to this checkout, `WORK` to existing scratch outside the checkout
and `SWC` to a Release compiler with its runtime.

```sh
git clone --depth 1 --branch 1.8.7 https://github.com/BLAKE3-team/BLAKE3.git "$WORK/blake3"
cc -O3 -I"$WORK/blake3/c" "$REPO/bench/workloads/blake3/reference.c" \
  "$WORK/blake3/c/blake3.c" "$WORK/blake3/c/blake3_dispatch.c" \
  "$WORK/blake3/c/blake3_portable.c" "$WORK/blake3/c/blake3_sse2_x86-64_unix.S" \
  "$WORK/blake3/c/blake3_sse41_x86-64_unix.S" "$WORK/blake3/c/blake3_avx2_x86-64_unix.S" \
  "$WORK/blake3/c/blake3_avx512_x86-64_unix.S" -o "$WORK/reference"

cd "$WORK"
SWAG_PATH="$REPO/bin" "$SWC" build -d "$REPO/bench/workloads/blake3/src" \
  --module-file "$REPO/bench/workloads/blake3/module.swg" -bc release \
  --artifact-kind executable --artifact-name swag-blake3 \
  --out-dir "$WORK/output" --work-dir "$WORK/build"
```

Select a CPU affinity mask allowed on your machine.

```sh
python3 -B "$REPO/bench/workloads/blake3/run.py" \
  --swag "w1=$WORK/output/swag-blake3" --swag "w2=$WORK/output/swag-blake3" \
  --swag "w4=$WORK/output/swag-blake3" --workers w2=2 --workers w4=4 \
  --reference "$WORK/reference" --cpu 0 --cpu 1 --cpu 2 --cpu 4 \
  --clock wall --rounds 11 --target-ms 35 --size 8388608 --size 33554432 \
  --scratch "$WORK" --output "$WORK/blake3-wall.json" --markdown "$WORK/blake3-wall.md"
```

Add `--algorithm blake3` for one-shot measurements. Select
`blake3-stream-4096`, `blake3-stream-65536` or `blake3-stream-1048576` for a
streaming size. Use `--verify-only --offset 1` to check unaligned input.
