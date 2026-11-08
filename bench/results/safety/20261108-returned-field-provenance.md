# Returned pointer-field provenance: compiler cost

The Linux DevMode compiler was tested before and after the `compiler.safety.023`
field-origin analysis. Both versions compiled the same external copy of the 53
sanity source files, with `borrow_free_carrier.swg` restored to its previous version.
Each run used `swc test --directory <copy> --no-test-jit --num-cores 3` and passed
all 89 tests. The runtime and standard library were the same for both compilers.

The earlier compiler SHA256 was
`cd3f8e5a731958766782c111d54666851c508c24e71619333317652b10d94951`;
the modified compiler SHA256 was
`00f08471767583f87d272993e81e7afb7fd8cb891f5960e2c09b8182cedd1206`.
After warmup, four pairs ran in alternating order. Each invocation passed the
repository's machine-load admission check. Wall time used `perf_counter`; CPU
time summed child user and system time for the compiler process.

| Version | Wall times (s) | CPU times (s) | Median wall (s) | Median CPU (s) |
| --- | --- | --- | ---: | ---: |
| Before | 1.060, 0.626, 1.198, 0.637 | 2.321, 1.470, 2.650, 1.451 | 0.849 | 1.896 |
| After | 0.644, 0.869, 0.770, 0.697 | 1.469, 1.969, 1.713, 1.542 | 0.734 | 1.628 |

No slowdown was resolved by this small campaign. The unchanged-before wall
samples varied from 0.626 to 1.198 seconds, so the median difference is not a
precise speed estimate. The added analysis runs only for returned structural
carriers and selected fields; a larger workload would be needed to bound its
worst-case cost.
