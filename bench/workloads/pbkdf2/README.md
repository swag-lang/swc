# PBKDF2-HMAC native comparison

The Linux comparison exercises PBKDF2 with HMAC-SHA-224, SHA-256, SHA-384
and SHA-512. Profiles include multiple output blocks, partial final blocks,
and passwords and salts that need more than one hash block. Each round uses
the same inputs, iteration count, and output length with both Swag builds
and Python's OpenSSL PBKDF2. The runner verifies every derived byte.

Set `swc` to an absolute path to the Release compiler with its matching
runtime beside it, and `baseline` and `candidate` to the two standard-library
revisions. The compared revisions need the Linux CPU clock binding from
`bfc8c126b5`. Use the probe from this checkout for both sides.
[Linux compiler setup](../../../tools/README.md#linux-compiler-build)

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
            -f "$root/bench/workloads/pbkdf2/src/pbkdf2.swg" \
            --module-file "$root/bench/workloads/pbkdf2/module.swg" \
            -bc release --artifact-kind executable -n pbkdf2-swag \
            -od "$side_dir/out" -wd "$side_dir/work")
done

python3 bench/workloads/pbkdf2/run.py --cpu 0 \
    --baseline "$work/baseline/out/pbkdf2-swag" \
    --candidate "$work/candidate/out/pbkdf2-swag" \
    --output "$work/results.json"
```

Set `--cpu` to a CPU in the process affinity. The timed span includes one
full derivation and its cleanup after an untimed warmup. The runner
shuffles the implementations in each round and saves CPU time, wall
time, exact median intervals, paired ratios, and the OpenSSL version.
