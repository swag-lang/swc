# Non-cryptographic hashes

This workload compares Swag's `Hash.City32.compute` and the byte overload of
`Hash.murmur3` with their upstream C++ counterparts. Both runs use seed zero and
serialize results in little-endian order. The CityHash32 comparison covers
inputs of at least five bytes. At lengths one through four, Swag interprets the
input as unsigned bytes while upstream interprets it as signed bytes. Core's
CityHash32 tests record Swag's output for that range.

The paired runner uses one Linux CPU. It checks every sampled result against
the upstream implementation and reports throughput, process CPU time and wall
time for repeated hashes of the same in-memory message. Process startup, file
I/O and one warm-up call are outside the timed interval.

## Build and run on Linux x86-64

Use an existing scratch directory outside the checkout for `WORK`, the repository
root for `REPO` and a Release compiler with its runtime for `SWC`.

```sh
git clone https://github.com/google/cityhash.git "$WORK/cityhash"
git -C "$WORK/cityhash" checkout --detach f5dc54147fcce12cefd16548c8e760d68ac04226
git clone https://github.com/aappleby/smhasher.git "$WORK/smhasher"
git -C "$WORK/smhasher" checkout --detach 07bb4de10a63e8cc2e1724865454eba635742383

mkdir -p "$WORK/city-build"
(cd "$WORK/city-build" && sh "$WORK/cityhash/configure")
c++ -O3 -std=c++17 -march=x86-64-v3 \
  -DCITYHASH_REVISION=\"$(git -C "$WORK/cityhash" rev-parse HEAD)\" \
  -DSMHASHER_REVISION=\"$(git -C "$WORK/smhasher" rev-parse HEAD)\" \
  -I"$WORK/city-build" -I"$WORK/cityhash/src" -I"$WORK/smhasher/src" \
  "$REPO/bench/workloads/noncryptohash/reference.cpp" \
  "$WORK/cityhash/src/city.cc" "$WORK/smhasher/src/MurmurHash2.cpp" \
  -o "$WORK/hash-reference"

cd "$WORK"
SWAG_PATH="$REPO/bin" "$SWC" build -d "$REPO/bench/workloads/noncryptohash/src" \
  --module-file "$REPO/bench/workloads/noncryptohash/module.swg" -bc release \
  --artifact-kind executable --artifact-name hashbench \
  --out-dir "$WORK/hash-bin" --work-dir "$WORK/hash-work"

python3 -B "$REPO/bench/workloads/noncryptohash/run.py" \
  --swag "candidate=$WORK/hash-bin/hashbench" --reference "$WORK/hash-reference" \
  --cpu 0 --scratch "$WORK" --output "$WORK/hash-results.json" \
  --markdown "$WORK/hash-results.md"
```

Pass multiple `--swag LABEL=PATH` arguments to compare builds in one campaign.
Use `--algorithm murmur64a` to include lengths below five bytes. Use `--offset 1`
to start the input at an odd address.
