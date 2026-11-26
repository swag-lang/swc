# Integrated Core crypto validation at 14:26 CET

The Linux x86-64 source snapshot was `b3fd1ff459`. It includes the
complete P-256 comb addition, the four-block Poly1305 update and the
published KMAC and AES changes. The Release compiler included SHA-NI
and the full-width multiplication instruction. Its SHA-256 fingerprint
was `f6dbb1036aae842b6bcb08ed394e68aacca8a6a70bb03b30a554258a6011fde1`.

The Core `/crypto/` selection included the AES-CCM, CRC-64 and scrypt
stress fixtures. The same cases ran in the JIT and the emitted native
program under each program configuration.

| Program configuration | JIT passed | Native passed | Failures |
| --- | ---: | ---: | ---: |
| Release | 154 | 154 | 0 |
| Release-safe | 154 | 154 | 0 |

The workspace and caches were staged outside the repository. The native
Release compiler command used the following options in each case.

```sh
swc test --workspace "$SNAPSHOT/bin/std" --workspace-module core \
  --artifact-kind executable --num-cores 2 --build-cfg release \
  --rebuild --run-timeout 1200 --test-file /crypto/ --test-jit
```
