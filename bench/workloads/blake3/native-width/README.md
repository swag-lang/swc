# Reproduce the native BLAKE3 width experiment

These patches reproduce the scratch compiler and library used in the
[2026-11-26 BLAKE3 width measurements](../../../results/crypto/20261126/blake3-native-width.md).
They apply to historical revision `d81f3cd6b547144b96afb334dc3ee4fde164fc8c`.
They implement the measured eight-lane u32 operations for an x86-64 AVX2
native experiment. The compiler patch also contains the half-open frame
object correction published in `0a186b3fed`.

Build on Linux x86-64 with GCC 14 or newer. Set `REPO` to the current
checkout and `WORK` to an existing directory outside the checkout. The
commands build three executables from the same compiler, reference input
and bench driver. The four-lane control uses the shipped 32-chunk cutoff.
The eight-lane variant uses the wide leaf whenever a full batch is
available. The hybrid uses the four-lane batch for shorter complete groups.

```sh
BASE=d81f3cd6b547144b96afb334dc3ee4fde164fc8c
DATA="$REPO/bench/workloads/blake3/native-width"
DRIVER="$REPO/bench/workloads/blake3"
mkdir -p "$WORK/source" "$WORK/narrow" "$WORK/wide" "$WORK/hybrid"
git -C "$REPO" archive "$BASE" src swc.vcxproj tools/linux-build.py bin/runtime |
  tar -x -C "$WORK/source"
xz -dc "$DATA/compiler.patch.xz" |
  (cd "$WORK/source" && git apply --ignore-space-change)

python3 -B "$WORK/source/tools/linux-build.py" --configuration release \
  --build-dir "$WORK/compiler" --cxx g++-14 --jobs 2
mkdir -p "$WORK/compiler/release/runtime"
cp -a "$WORK/source/bin/runtime/." "$WORK/compiler/release/runtime/"
SWC="$WORK/compiler/release/swc"

for variant in narrow wide hybrid; do
  git -C "$REPO" archive "$BASE" bin/std/modules/core bin/std/modules/linux |
    tar -x -C "$WORK/$variant"
  xz -dc "$DATA/control.patch.xz" |
    (cd "$WORK/$variant" && git apply --ignore-space-change)
  case "$variant" in
    wide)
      xz -dc "$DATA/width8.patch.xz" |
        (cd "$WORK/$variant" && git apply --ignore-space-change) ;;
    hybrid)
      xz -dc "$DATA/hybrid.patch.xz" |
        (cd "$WORK/$variant" && git apply --ignore-space-change) ;;
  esac
  mkdir -p "$WORK/$variant/tmp"
  SWAG_PATH="$WORK/$variant/bin" TMPDIR="$WORK/$variant/tmp" \
    "$SWC" build -d "$DRIVER/src" --module-file "$DRIVER/module.swg" \
    -bc release --artifact-kind executable --artifact-name swag-blake3 \
    --out-dir "$WORK/$variant/out" --work-dir "$WORK/$variant/build" -j 1
done
```

Build BLAKE3 C 1.8.7 using the [standard BLAKE3 reference instructions](../README.md).
The one-worker run measures process CPU time on one allowed logical CPU.
Use the same CPU and the same reference executable for all three builds.

```sh
python3 -B "$DRIVER/run.py" --algorithm blake3 \
  --reference "$WORK/reference" --cpu 1 --clock cpu \
  --swag "narrow=$WORK/narrow/out/swag-blake3" \
  --swag "wide=$WORK/wide/out/swag-blake3" \
  --swag "hybrid=$WORK/hybrid/out/swag-blake3" \
  --rounds 13 --target-ms 18 --offset 0 --offset 1 \
  --size 4096 --size 4097 --size 8191 --size 8192 --size 32769 \
  --size 65536 --size 1048576 --size 8388608 \
  --scratch "$WORK" --output "$WORK/blake3-native-width-cpu.json"
```

Build the optional oneTBB reference from the same README for the
four-worker wall comparison. Select four logical CPUs allowed in your
environment.

```sh
python3 -B "$DRIVER/run-tbb.py" --reference "$WORK/tbb-reference/reference" \
  --swag "narrow=$WORK/narrow/out/swag-blake3" \
  --swag "wide=$WORK/wide/out/swag-blake3" \
  --swag "hybrid=$WORK/hybrid/out/swag-blake3" \
  --workers narrow=4 --workers wide=4 --workers hybrid=4 \
  --cpu 0 --cpu 1 --cpu 2 --cpu 3 --clock wall --rounds 11 --target-ms 17 \
  --size 8388608 --size 33554432 --offset 0 \
  --scratch "$WORK" --output "$WORK/blake3-native-width-wall.json"
```

The compiler probes hold each native 256-bit value in a local or pass it
in memory. They cover 22 live wide values, unaligned memory, wide shuffles
and rotates, constant stores and leaf chaining values. The
`packed-leaf-in` probe calls a transpose helper with wide values live across
the call. It checks the carry across that call against 64 words from the
official BLAKE3 C leaf routine.

```sh
mkdir -p "$WORK/probes"
tar -x -f "$DATA/probes.tar.xz" -C "$WORK/probes"
for cfg in release release-safe; do
  for probe in const-store-probe pair-shuffle-probe pair-leaf-probe \
               packed-leaf-in probe ops-probe; do
    "$SWC" run -d "$WORK/probes/$probe" -bc "$cfg" \
      --artifact-kind executable --artifact-name validate-width \
      --out-dir "$WORK/$probe-$cfg/out" --work-dir "$WORK/$probe-$cfg/build" -j 1
  done
  SWAG_PATH="$WORK/hybrid/bin" "$SWC" run -d "$WORK/probes/staggered" \
    --module-file "$DRIVER/module.swg" -bc "$cfg" --artifact-kind executable \
    --artifact-name validate-xof --out-dir "$WORK/staggered-$cfg/out" \
    --work-dir "$WORK/staggered-$cfg/build" -j 1
done
```
