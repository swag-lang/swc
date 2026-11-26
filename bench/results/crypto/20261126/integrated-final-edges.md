# Final differential checks at byte boundaries

The Release build of `10bf72c650` matched its references byte for byte
on all 836 cases across 19 operations and two nonzero input offsets.
The same references used in the final timing panel cover the checksums,
message digests, ciphertext and authentication tags. Both passes use
identical generated inputs at the following logical message sizes.

`0, 1, 7, 15, 16, 31, 32, 55, 56, 63, 64, 65, 127, 128, 255, 511, 512, 1023, 1024, 4095, 4096, 8193`

Run the common workload with `--verify-only`, once with `--offset 1`
and once with `--offset 7`. Use one `--size` argument for each size
above and select the original 19 algorithms from the final panel.
The JSON records each input and full output fingerprint.

[Offset 1 results](integrated-final-edges-offset1.json) · [Offset 7 results](integrated-final-edges-offset7.json) · [Final timings](integrated-final.md) · [Reproduction](../../../workloads/crypto/README.md)
