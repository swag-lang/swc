# Cached inverse round keys for AES-XTS

AES-XTS prepares the inverse decryption schedule once per data unit.
Each packed batch reuses it, including the ciphertext-stealing path.
The key material is cleared at scope exit.

With OpenSSL 4.1.0 as the exact reference, the native Release 1 MiB
decryption rate increased from 4.98 to 5.77 GB/s. The paired gain was
1.16× [1.13, 1.18]. OpenSSL reached 13.6 GB/s. Encryption and the
short-record profiles had paired intervals that included parity.

The 56 unaligned inputs per direction matched OpenSSL byte for byte.
Thirty-seven focused AES cases passed native Release and Release-safe
on the host and with AES and PCLMUL disabled under QEMU.

[Raw paired trials](aes-xts-inverse-schedule.json) · [External verification](aes-xts-inverse-schedule-verification.json).
