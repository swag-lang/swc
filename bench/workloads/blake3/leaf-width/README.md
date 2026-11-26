# BLAKE3 leaf compression width

This workload compiles one portable C++ schedule into SSE4.1 with four lanes
and AVX2 with four or eight lanes. Each result is the complete array of leaf
chaining values. BLAKE3 C 1.8.7 also produces the leaf values and checks them
byte for byte before and after each sample. The fixtures cover unaligned
addresses, a 32-bit chunk-counter carry and keyed leaf compression.

Use GCC 14 or later on Linux x86-64 with AVX2. Set `REPO` to the checkout
and `WORK` to a scratch directory outside it.

```sh
git clone --depth 1 --branch 1.8.7 https://github.com/BLAKE3-team/BLAKE3.git "$WORK/blake3"
DRIVER="$REPO/bench/workloads/blake3/leaf-width"
bash "$DRIVER/build.sh" "$WORK/blake3/c" "$WORK/leaf-width"
python3 -B "$DRIVER/run.py" --binary "$WORK/leaf-width/blake3-width" \
  --cpu 1 --output "$WORK/blake3-leaf-width.json"
```

Replace `--cpu 1` with a CPU allowed by your affinity mask. The runner
records wall and process CPU samples. Throughput uses process CPU time
and excludes input creation, validation, the BLAKE3 tree and finalization.
