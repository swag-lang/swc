# Argon2 native lane scaling

Run from the repository root:

```powershell
bin/swc.dm.exe test -f src/argon2.test.swg --module-file bench/workloads/argon2/module.swg -bc release --no-test-jit
```

The native test derives a 32-byte Argon2id tag with four lanes and three passes. It uses the
same scalar compression kernel, input, allocation, clearing and parameters for one and four
runtime workers. Each profile has one untimed warm-up and three timed samples; every tag must
match the one-worker result. Pool startup is outside the timer. The test runs the one-worker
profiles first because the runtime pool can grow but cannot shrink. These are local timing
samples, not an interleaved machine-wide performance campaign.

The 256 MiB profile matches Swag Vault's production slot-key costs. Its unit-test profile uses
one lane and 32 KiB, so ordinary Vault unit tests do not measure that production computation.

Measured 2026-09-08 06:30 on an Intel Core Ultra 9 185H, using the DevMode compiler and the
`release` program configuration:

| Memory | One-worker samples (us) | Four-worker samples (us) | Median speedup |
| --- | --- | --- | --- |
| 64 MiB | 204105, 206413, 209873 | 72815, 70645, 70480 | 2.92x |
| 256 MiB | 858210, 862168, 862776 | 311284, 308269, 305569 | 2.80x |

To evaluate a future SIMD kernel, compare it at the same worker count. Changing lane count
changes the derived key and is not a sequential baseline.

After moving small-work decisions into the runtime on 2026-09-08, the same benchmark body
ran from a standalone native entry with assertions enabled, admitted at 3% average CPU:

| Memory | One-worker samples (us) | Four-worker samples (us) | Median speedup |
| --- | --- | --- | --- |
| 64 MiB | 190966, 195349, 200563 | 70079, 72993, 79346 | 2.68x |
| 256 MiB | 829440, 822876, 840635 | 307849, 301276, 321023 | 2.69x |

The runtime still distributes these expensive four-iteration ranges. Argon2 no longer needs
its own segment-length threshold; one-lane work stays local through the runtime's single-index
fast path. As with the earlier samples, the runs are local evidence rather than a pinned campaign.

## Native comparison with libargon2 and OpenSSL

The Linux runner pairs one native Swag run with both independent libraries in every round.
It verifies the full 32-byte tag on each run. All profiles use four lanes, three passes,
and Argon2 version 0x13. The worker count sets available CPU threads independently of lanes.
The timer includes the derivation's allocation, computation, and internal clearing. It
excludes one warm-up derivation, worker-pool startup in Swag, and provider setup in OpenSSL.

From the repository root, set `swc` to an absolute path to the Release compiler with its
matching runtime beside it. Set `baseline` and `candidate` to the two revisions to compare.
The probe source comes from this checkout for both builds. [Linux compiler setup](../../../tools/README.md#linux-compiler-build)

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
            -f "$root/bench/workloads/argon2/compare/compare.swg" \
            --module-file "$root/bench/workloads/argon2/module.swg" \
            -bc release --artifact-kind executable -n argon2-swag \
            -od "$side_dir/out" -wd "$side_dir/work")
done
```

Build the upstream library with the target selected for the machine under test. The probe
also needs OpenSSL 3.2 or newer with Argon2id and threading enabled.

```sh
git clone --depth 1 --branch 20190702 https://github.com/P-H-C/phc-winner-argon2.git "$work/libargon2"
make -C "$work/libargon2" OPTTARGET=native libargon2.a
cc -std=c11 -O2 -I"$work/libargon2/include" \
    bench/workloads/argon2/compare/reference.c "$work/libargon2/libargon2.a" \
    -pthread -lcrypto -o "$work/argon2-reference"

python3 bench/workloads/argon2/compare/run.py \
    --baseline "$work/baseline/out/argon2-swag" \
    --candidate "$work/candidate/out/argon2-swag" \
    --reference "$work/argon2-reference" --cpus 0 1 2 3 \
    --output "$work/results.json"
```

Replace the four CPU IDs with CPUs from the process affinity. The one-worker run uses the
first CPU and the four-worker run uses the whole set. The default nine rounds shuffle the
implementations within each round. The JSON keeps per-round times, exact median intervals,
and paired candidate/reference ratios for 1, 64, and 256 MiB.
