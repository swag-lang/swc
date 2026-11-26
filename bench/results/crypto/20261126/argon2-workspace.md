# Argon2id compression workspace reuse

Each lane segment owns one packed compression workspace. Every compression
replaces all workspace pairs before permuting them. Address generation shares
the workspace and reads each input pair before publishing output, including the
call that overwrites its right input. The worker securely clears the workspace
before its lane segment completes.

Both Swag builds used native Release. The standard library baseline was
`51fc17f2fe`. Each call used four Argon2id lanes, three passes, version 0x13 and
a 32-byte tag. The comparison used thirteen shuffled paired rounds per profile
on an AMD EPYC 9V74 under Linux 6.18.57. Single-worker runs used CPU 2.
Four-worker runs shared CPUs 0–3. The table shows median process CPU times
in milliseconds and paired 95% time-ratio intervals.

| MiB | Workers | Before | Reused | libargon2 AVX-512 | OpenSSL 3.5.7 | Reused / before |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 1.456 | 1.401 | 0.834 | 1.596 | 0.971 [0.934, 0.993] |
| 64 | 1 | 122.377 | 119.510 | 88.936 | 142.877 | 0.969 [0.958, 1.006] |
| 256 | 1 | 681.037 | 660.143 | 455.179 | 679.132 | 0.947 [0.823, 1.126] |
| 1 | 4 | 2.834 | 2.618 | 2.421 | 2.283 | 0.911 [0.903, 1.030] |
| 64 | 4 | 161.409 | 154.545 | 82.149 | 115.806 | 0.941 [0.843, 1.018] |

The 1 MiB single-worker profile used 2.9% less CPU and 3.2% less elapsed
time. A separate 25-round run of that profile found 4.9% less CPU
with a time ratio of 0.951 [0.932, 0.963] and 5.5% less elapsed time
with a ratio of 0.945 [0.927, 0.963]. The other profiles' paired intervals
span parity for both clocks. libargon2 used less CPU at the two larger
sizes.

Every measured tag matched both references. Six focused native Release
Core cases passed. A parallel Release-safe compile reported an internal
Sema error. The same six native Release-safe cases then passed on
both builds with one compiler thread.

[Reproduction](../../../workloads/argon2/README.md#native-comparison-with-libargon2-and-openssl) · [Raw times and tags](argon2-workspace.json)
