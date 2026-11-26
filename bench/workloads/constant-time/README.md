# Constant-time equality comparison

The workload compares `Crypto.constantTimeEqual` with OpenSSL's
`CRYPTO_memcmp` and libsodium's `sodium_memcmp` on Linux x86-64.
Both input buffers have the same length. Each implementation returns
one byte that indicates equality. Use `ct-equal`, `ct-first`, and
`ct-last` to select identical input, a first-byte mismatch, or a
last-byte mismatch. Buffer preparation, warm-up, and output verification
sit outside the timer.

Set `swc` to the Release compiler with its adjacent runtime, and
`baseline` and `candidate` to the standard library revisions to compare.
Install the OpenSSL and libsodium development packages.

```sh
root="$PWD"
work=$(mktemp -d)
workload="$root/bench/workloads/constant-time"
cc -std=c11 -O3 -Wall -Wextra -Werror "$workload/reference.c" \
  $(pkg-config --cflags --libs openssl libsodium) -o "$work/reference"

for side in baseline candidate
do
    if [ "$side" = baseline ]
    then
        revision="$baseline"
    else
        revision="$candidate"
    fi
    mkdir -p "$work/$side"
    git archive "$revision" bin/std | tar -x -C "$work/$side"
    (cd "$work/$side" &&
        SWAG_PATH="$work/$side/bin" "$swc" build -d "$workload/src" \
            --module-file "$workload/module.swg" -bc release \
            --artifact-kind executable -n swag-constant-time \
            -od "$work/$side/out" -wd "$work/$side/work")
done

python3 -B "$workload/run.py" --cpu 0 --scratch "$work" \
  --reference "$work/reference" \
  --swag "baseline=$work/baseline/out/swag-constant-time" \
  --swag "candidate=$work/candidate/out/swag-constant-time" \
  --algorithm ct-equal --algorithm ct-first --algorithm ct-last \
  --size 16 --size 32 --size 64 --size 4096 --output "$work/results.json"

(cd "$work/candidate/out" && ./swag-constant-time --guard)
```

`--guard` puts the inputs against inaccessible pages. It tests both ends
of a mapped page for all lengths from 0 through 257, including every
single-byte mismatch and comparisons against an empty sequence.

Inspect the generated Linux Release function with `objdump`.

```sh
objdump -d -M intel --disassemble=__swc_api_636f7265__crypto__constant_time_equal \
  "$work/candidate/bin/std/.output/core/shared-library/release/x86_64/core.so"
```

[Shared timing and sampling details](../crypto/README.md)
