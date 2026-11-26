# KDF comparison with native references

The replay uses the existing scrypt and PBKDF2 fixtures. It compares each
of two native Swag executables with Python's OpenSSL and an additional
native library. scrypt uses libsodium's low-level function with explicit
`N`, `r` and `p`. PBKDF2 uses four HMAC-SHA-2 variants in Nettle.
The runner verifies every output byte in each round.

Install the Nettle and libsodium development packages. Set `work` to an
absolute scratch directory. Build both Swag executables with the same
Release compiler using the corresponding workload's instructions.

- [scrypt probe and build instructions](../scrypt/README.md)
- [PBKDF2 probe and build instructions](../pbkdf2/README.md)

Set `baseline` and `candidate` to the two executable paths, and `workload`
to `scrypt` or `pbkdf2`.

```sh
cc -std=c11 -O3 -fPIC -shared -Wall -Wextra -Werror \
  bench/workloads/kdf-replay/reference.c \
  $(pkg-config --cflags --libs nettle libsodium) -o "$work/reference.so"

python3 -B bench/workloads/kdf-replay/run.py "$workload" --cpu 0 \
  --baseline "$baseline" --candidate "$candidate" \
  --reference "$work/reference.so" --output "$work/kdf-replay.json"
```

One untimed derivation precedes each measurement. Implementations run in
shuffled order and use the same Linux CPU affinity. The C calls through
Python are included in the native library measurements. Each reference
allocates and cleans up through its normal API.

## Standalone OpenSSL versions

The same probe can link two versions of OpenSSL for a native comparison.
Build the probe once per library. Set `openssl_dir` to the configured
OpenSSL source directory containing its headers and `libcrypto.a`.

```sh
cc -std=c11 -O3 -Wall -Wextra -Werror   -I"$openssl_dir/include" bench/workloads/kdf-replay/openssl-reference.c   "$openssl_dir/libcrypto.a" -pthread -ldl -o "$work/openssl-reference"
```

Add `--openssl-native "$work/openssl-reference"` to the replay. Repeat
the option for each version to include. Each native executable times
one complete derivation after a warm-up.
