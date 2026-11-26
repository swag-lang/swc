# Packed AES-XTS tweak doubling

A signed-lane shift and shuffle supply the carry and polynomial-reduction
mask for the next XTS tweak. This applies while processing independent
data blocks and while handling a final partial block.

At 1 MiB the paired encryption speedup was 1.13× [1.01, 1.18] at 5.77
GB/s. Decryption was 1.09× [1.08, 1.10] at 5.03 GB/s. The raw panel
also includes the independent CMAC screening arms.

The exact XTS candidate matched OpenSSL for 60 unaligned cases per
direction. The 36 focused AES cases passed in native Release and
Release-safe, and in both configurations with AES and PCLMUL disabled
under QEMU.

[Raw paired trials](aes-xts-doubling.json) · [External verification](aes-xts-doubling-verification.json).
