# Integrated BLAKE3 boundary validation

The frozen source `10bf72c650` matched BLAKE3 C 1.8.7 on 276
message, alignment, and operation combinations with both one and four
configured Swag workers. The panel used 23 message lengths from zero
through 32 MiB, offsets 0, 1 and 15, and four operation profiles.
Streaming passed the input in 4 KiB, 64 KiB or 1 MiB slices.
Six large one-shot comparisons also matched BLAKE3 C with oneTBB 2022.1.0.
[Streaming and one-shot outputs](blake3-integrated-stream-verify.json) ·
[oneTBB outputs](blake3-integrated-tbb-verify.json)

The Linux guard-page fixture passed in Release and Release-safe. It
places each of 16 message lengths against either edge of a read-only
mapping bordered by inaccessible pages. For each placement it checks
both one-shot and split streaming output against BLAKE3 C, for 64 digest
checks per configuration. The lengths surround the partial SIMD batch
boundaries at 2, 3 and 4 KiB and include tails after a full batch.
The 131-byte unkeyed, keyed and derived-key fixture also passed in both
configurations. The focused native Core suite passed seven tests in
Release-safe. [Guard fixture](../../../workloads/blake3/guard-src/guards.swg) ·
[Integrated validation](integrated-validation-final.md)

## Replay

Build the drivers and references from the frozen revision using the
[standard BLAKE3 commands](../../../workloads/blake3/README.md).
The observed compiler executable had SHA-256
`e0e8fb233c045d296d4de002c583b17c276b7340e3a71d3f3a9d4ce714d2e5eb`.
Set `REPO` to the checkout that contains this report, `FROZEN` to the
archived `10bf72c650` source, `SWC` to the integrated Release compiler
with its adjacent runtime, and `WORK` to an external scratch directory.
The guard fixture uses Linux with 4 KiB pages.

```sh
DRIVER="$REPO/bench/workloads/blake3"
mkdir -p "$WORK/tmp" "$WORK/probes"
tar -xJf "$DRIVER/native-width/probes.tar.xz" -C "$WORK/probes" ./staggered
for cfg in release release-safe; do
  SWAG_PATH="$FROZEN/bin" TMPDIR="$WORK/tmp" "$SWC" run \
    -d "$DRIVER/guard-src" --module-file "$DRIVER/module.swg" \
    -bc "$cfg" --artifact-kind executable --artifact-name validate-guard \
    --out-dir "$WORK/guard-$cfg/out" --work-dir "$WORK/guard-$cfg/build" -j 1
  SWAG_PATH="$FROZEN/bin" TMPDIR="$WORK/tmp" "$SWC" run \
    -d "$WORK/probes/staggered" --module-file "$DRIVER/module.swg" \
    -bc "$cfg" --artifact-kind executable --artifact-name validate-xof \
    --out-dir "$WORK/xof-$cfg/out" --work-dir "$WORK/xof-$cfg/build" -j 1
done

SWAG_PATH="$FROZEN/bin" TMPDIR="$WORK/tmp" "$SWC" test \
  --workspace "$FROZEN/bin/std" --workspace-module core -bc release-safe \
  --artifact-kind executable --no-test-jit --test-file crypto/blake3.swg -j 1
```

For the differential panel, pass the same Release binary under two
`--swag` labels and set the second label to four workers with `--workers`.
Use `--verify-only`, an affinity mask with four allowed CPUs, and the
sizes and offsets in the raw outputs. Use `run-tbb.py` for the oneTBB
reference. The keyed fixture also requires four allowed CPUs.
