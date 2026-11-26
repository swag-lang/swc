# Reproduce the eight-lane ChaCha20 experiment

The consumer patch is tested with the archived AVX2 compiler from the
[BLAKE3 width campaign](../../blake3/native-width/README.md). The
[ChaCha20 report](../../../results/crypto/20261126/chacha20-native-width.md)
records the baseline, exactness checks and timings. The experimental
path keeps eight independent blocks in 256-bit rows, then unpacks each
word group into increasing output block order.

Build the experimental Release compiler from revision
`d81f3cd6b547144b96afb334dc3ee4fde164fc8c` using the compiler steps in
the BLAKE3 instructions. Set `REPO` to the checkout, `WORK` to an
existing external directory, and `SWC` to the experimental compiler
with its adjacent runtime.

```sh
BASE=d81f3cd6b547144b96afb334dc3ee4fde164fc8c
DATA="$REPO/bench/workloads/crypto/native-width"
mkdir -p "$WORK/driver" "$WORK/narrow" "$WORK/wide"
git -C "$REPO" archive "$BASE" bench/workloads/crypto | tar -x -C "$WORK/driver"
DRIVER="$WORK/driver/bench/workloads/crypto"

for variant in narrow wide; do
  git -C "$REPO" archive "$BASE" bin/std/modules/core bin/std/modules/linux |
    tar -x -C "$WORK/$variant"
  git -C "$REPO" show --format= b0608717e9 -- \
    bin/std/modules/core/src/crypto/chacha20.swg \
    bin/std/modules/core/src/tests/cases/functional/crypto/chacha20.swg |
    (cd "$WORK/$variant" && git apply --ignore-space-change)
  if [ "$variant" = wide ]; then
    xz -dc "$DATA/width8.patch.xz" |
      (cd "$WORK/$variant" && git apply --ignore-space-change)
  fi
  SWAG_PATH="$WORK/$variant/bin" "$SWC" build -d "$DRIVER/src" \
    --module-file "$DRIVER/module.swg" -bc release --artifact-kind executable \
    -n swag-crypto --out-dir "$WORK/$variant/out" --work-dir "$WORK/$variant/build" -j 1
done
```

Build the OpenSSL 4.1 reference using the
[crypto benchmark instructions](../README.md). The timings use one
allowed CPU and one worker. The campaign also checked outputs with
libsodium 1.0.22 via `crypto_stream_chacha20_ietf_xor_ic` and
`crypto_aead_chacha20poly1305_ietf_encrypt` with the driver's key,
nonce, associated data and initial counter.

```sh
python3 -B "$REPO/bench/workloads/crypto/run.py" \
  --swag "narrow=$WORK/narrow/out/swag-crypto" \
  --swag "wide=$WORK/wide/out/swag-crypto" --reference "$WORK/reference" \
  --cpu 0 --clock cpu --rounds 15 --target-ms 22 --offset 0 --offset 1 \
  --algorithm chacha20 --algorithm chacha20-poly1305 \
  --size 64 --size 511 --size 512 \
  --size 1024 --size 4096 --size 16384 --size 4194304 \
  --scratch "$WORK" --output "$WORK/chacha20-native-width.json"
```
