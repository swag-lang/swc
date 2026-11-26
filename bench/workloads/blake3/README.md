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

## One-shot scaling against oneTBB

Install the oneTBB development library (Debian's `libtbb-dev`) for this
optional run. BLAKE3 C calls its official parallel update API with oneTBB
global concurrency limits of 2 or 4. The limit includes the calling thread.
All processes use the CPU mask supplied to the runner. It records process
CPU time alongside wall time, so the measured CPU usage can be compared
with the configured limits.

Reuse the BLAKE3 C checkout and Swag binary from the serial build. Compile
the reference in scratch with a C++ driver for the oneTBB object and link.

```sh
mkdir -p "$WORK/tbb-reference"
cd "$WORK/tbb-reference"
CC_SRC="$WORK/blake3/c"
DRIVER="$REPO/bench/workloads/blake3"
cc -O3 -DBLAKE3_USE_TBB -I"$CC_SRC" -c "$DRIVER/reference.c" \
  "$CC_SRC/blake3.c" "$CC_SRC/blake3_dispatch.c" "$CC_SRC/blake3_portable.c" \
  "$CC_SRC/blake3_sse2_x86-64_unix.S" "$CC_SRC/blake3_sse41_x86-64_unix.S" \
  "$CC_SRC/blake3_avx2_x86-64_unix.S" "$CC_SRC/blake3_avx512_x86-64_unix.S"
c++ -O3 -fno-exceptions -DBLAKE3_USE_TBB -I"$CC_SRC" $(pkg-config --cflags tbb) \
  -c "$DRIVER/tbb-limit.cpp" "$CC_SRC/blake3_tbb.cpp"
c++ ./*.o $(pkg-config --libs tbb) -o reference

python3 -B "$DRIVER/run-tbb.py" \
  --swag "w1=$WORK/output/swag-blake3" --swag "w2=$WORK/output/swag-blake3" \
  --swag "w4=$WORK/output/swag-blake3" --workers w2=2 --workers w4=4 \
  --reference "$WORK/tbb-reference/reference" --cpu 0 --cpu 1 --cpu 2 --cpu 4 \
  --clock wall --rounds 11 --target-ms 25 --size 8388608 --size 33554432 \
  --size 67108864 --scratch "$WORK" --output "$WORK/blake3-tbb-wall.json" \
  --markdown "$WORK/blake3-tbb-wall.md"
```

The Markdown table selects the fastest comparator for each input. The JSON
stores samples for all three C variants and all three Swag worker counts.
