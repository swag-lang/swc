# scrypt native comparison

Compare native Swag builds and the OpenSSL scrypt exposed by Python's `hashlib`.
The probe uses one worker and one lane for all three ROMix working sets, from
128 KiB through 64 MiB. Each sample includes allocation, derivation, and secure
clearing. A warm-up call precedes the timed call. The runner checks every full
32-byte derived tag and records process CPU and wall time.

Set `swc` to an absolute path to the Release compiler with its matching runtime
beside it. Set `baseline` and `candidate` to the two standard-library revisions.
Both need the Linux process CPU clock constant introduced at `bfc8c126b5`.
Use the probe from this checkout for both builds. [Linux compiler setup](../../../tools/README.md#linux-compiler-build)

```sh
root="$PWD"
work=$(mktemp -d)
mkdir -p "$work/baseline" "$work/candidate"
git archive "$baseline" bin/std | tar -x -C "$work/baseline"
git archive "$candidate" bin/std | tar -x -C "$work/candidate"
for side in baseline candidate
do
    side_dir="$work/$side"
    (cd "$side_dir" &&
        SWAG_PATH="$side_dir/bin" "$swc" build \
            -f "$root/bench/workloads/scrypt/src/scrypt.swg" \
            --module-file "$root/bench/workloads/scrypt/module.swg" \
            -bc release --artifact-kind executable -n scrypt-swag \
            -od "$side_dir/out" -wd "$side_dir/work")
done

python3 bench/workloads/scrypt/run.py --cpu 0 \
    --baseline "$work/baseline/out/scrypt-swag" \
    --candidate "$work/candidate/out/scrypt-swag" \
    --output "$work/results.json"
```

Set `--cpu` to a CPU in the process affinity. The default nine rounds shuffle the
implementations within each round. The JSON records the OpenSSL version, the
samples, exact median intervals, and paired latency ratios.
