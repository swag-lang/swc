# Consistent VEX encoding at AVX boundaries

The x64 encoder now uses VEX for its scalar and 128-bit vector operations. This removes the
legacy SSE/AVX transition penalty after ABI-compliant foreign calls or callbacks that leave
upper YMM state dirty. The existing AVX target requirement is unchanged. Scalar register moves
preserve their merge lanes; memory loads clear them. Floating-point policy is unchanged.

Measurements compare rebuilt Release compilers at `41f03296f` with the three source changes
preserved in `7a509e062`, on a Core Ultra 9 185H. Acceptance uses **Release program performance**.
Processes are pinned to CPU 0. Alternating baseline/candidate/unchanged-control launches use
at most six compiler workers, measured load admission and a 15% background-CPU cutoff for timing.
Raw accepted and rejected Release samples are in [release-samples.json](release-samples.json).
The original helper and probe method are retained in
[the preceding investigation](../20261005-runtime-layout/README.md).

## Dirty upper-state boundary

Each process alternates 15 dirty/clean 5,000-step nbody calls; three process launches per tag.
Every checksum is `169020000371`. The helper preserves XMM15's nonvolatile lower half.
Milliseconds below are medians of accepted process medians.

| Boundary | Baseline dirty | Candidate dirty | Candidate clean |
| --- | ---: | ---: | ---: |
| native | 23.0598 | 0.1626 | 0.1605 |
| callback | 22.2283 | 0.1649 | 0.1623 |
| jit | 23.8487 | 0.1829 | 0.1979 |
| jit_callback | 23.2048 | 0.1745 | 0.1740 |

## Ordinary Release sentinels

A broad first window was stopped when the owner requested shorter iterations; do not treat it as
a completed benchmark campaign. The two suspicious cases were repeated in an independent fixed
15-pair window. Percentages are paired candidate/baseline and unchanged-control/baseline medians;
positive means slower. All numerical results match. These noisy windows do not establish a
general speedup or a reproducible Release regression. They are retained in full for these
Release samples, including rejected load windows.

| Program / window | Pairs | Candidate | Control |
| --- | ---: | ---: | ---: |
| chacha / first | 21 | +0.77% | -0.52% |
| csvagg / first | 21 | +6.19% | +0.94% |
| dijkstra / first | 21 | +2.89% | +3.56% |
| fannkuch / first | 15 | +1.94% | +0.97% |
| leven / first | 21 | -0.92% | +1.16% |
| nbody / first | 21 | +0.91% | +2.36% |
| raytrace / first | 21 | +2.45% | -3.36% |
| sha256 / first | 21 | -0.32% | -0.14% |
| wordfreq / first | 21 | -3.71% | -1.88% |
| csvagg / repeat | 15 | +2.76% | +2.49% |
| raytrace / repeat | 15 | -0.15% | -4.83% |

Across the 24 built benchmark images (both presets), an instruction audit found no remaining
legacy XMM instructions in candidate text. Median executable size changes by -0.14%, text by
+0.75%; the Release compiler executable grows by 1,536 bytes. Compiler-time measurement was
intentionally omitted to keep iteration short. This experiment does not identify the cause
of the historical Oct 5 unmodified JIT timing change.

Validation before integration: 1,343 C++ tests, native suites with 3,619 tests in each preset,
and native/JIT direct and callback dirty-state probes. After bringing in current master, the
Release compiler builds and the focused native `float` selection passes 37 tests in Release.
The byte goldens cover extended registers, indexed addressing, conversions and relocations;
a JIT regression covers scalar merge/zero behavior and untouched signaling-NaN payloads.
