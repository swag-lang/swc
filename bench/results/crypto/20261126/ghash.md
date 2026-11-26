# Carry-less GHASH reduction

The revised kernel reduces the full 256-bit product using two polynomial folds and keeps
each record's GHASH accumulator in the CLMUL coefficient order across full blocks.
The eight native Release AES-GCM tests passed, including NIST known answers, scalar/CLMUL
comparison, in-place operation, invalid tags and large-record coverage.

On CPU 2 of the AMD EPYC 9V74 Linux host, seven native Release trials per build processed
1 MiB through the chained GHASH loop. Timing series were run separately. The median dropped
from 51343 to 739 microseconds, a 69.5x speedup
(95% CI 32.5–148.4x). Full AES-GCM still used software AES. The common
comparison measures complete records against OpenSSL.

[Raw GHASH trials](ghash.json).
