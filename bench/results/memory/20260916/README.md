# Compiler memory campaign - 2026-09-16

## Batch 1: compact sanitizer records

Reorder fields without removing facts or changing the analysis. `SanitizerLocation` shrinks
from 32 to 24 bytes and keeps its previous comparison order. `SanitizerRegInfo` shrinks from
176 to 128 bytes in the Release compiler, and from 208 to 152 in DevMode. Static assertions
protect the new layouts. Optimizer settings and generated-code transformations are unchanged.

The isolated comparison uses master `2eefc93ce` (build 688) and that revision plus this
layout change (build 689). Both compiler executables were built with normal project settings;
performance measurements use the Release compiler. SHA-256:

- Baseline: `56F37503F5B82CBAC65725EE0C350E9B926113183AECE229702C6508EE79B184`.
- Candidate: `E260B74FF954C761E5A46E46C0E258B085FF9E8FE08341A1EBDCAA2DB2D3BE4F`.
- Candidate DevMode: `3BA82C30FF5D89EA42BD631D978198DA574DB78C5C271C59F6EECE4DB541F3BC`.

### Measurements

The workload rebuilds `bin/std` module `core`, separately with `-bc devmode` and `-bc release`,
using `--rebuild --silent --num-cores 6`. Each round alternates A/B and B/A. Every command
passes the machine-load guard with a stricter 20% CPU threshold and the normal memory limits.
The Windows job harness in `bench/winproc.py` records elapsed time, process CPU time, peak
working set and peak committed memory for the job. MiB means 1,048,576 bytes.

The first five-pair unpinned series was inconclusive for devmode speed: median paired elapsed
time rose 7.1%, while CPU time rose 1.1%. Hybrid-core placement and concurrent work produced
large variation. It remains in [layout-unpinned.json](layout-unpinned.json); no samples were
discarded. A separate seven-pair series fixes the same six performance cores for both binaries
using the harness's topology-derived mask. This affinity is only a measurement control, not a
compiler behavior change. [All controlled samples](layout-pinned.json).

| Program configuration | Baseline peak WS MiB | Candidate peak WS MiB | Paired peak WS change | Paired commit change | Paired elapsed change | Paired CPU change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| devmode | 662.7 | 569.9 | -14.4% | -13.8% | -1.4% | -6.5% |
| release | 330.1 | 325.8 | -2.4% | -2.1% | -5.4% | -6.1% |

Absolute values are medians; changes are medians of same-round B/A ratios. Shared-machine
activity can start after admission, so the raw elapsed times still vary substantially.
The controlled series shows no median compile-time regression in either configuration.
These are results for this workload and host, not a guarantee for every input.

PE section sizes and hashes are retained with each controlled sample. Even two baseline
rebuilds differ in native byte ordering and occasionally `.text` size; byte identity is not
claimed. This change preserves all analysis data, checks and code-generation passes.

### Functional validation

- Release and DevMode compiler builds passed.
- DevMode compiler C++ suite: 860 tests passed.
- Static sanity suite, program devmode: 57 tests passed with each compiler executable.
- DevMode compiler native suite, program devmode: 3,249 tests passed, including execution of
  the linked executable; the tool's expected recovery probes also passed.
- Native suite, program release: 3,248 passed, one failed in `types/type_patterns.swg:254`.
  The frozen baseline reproduces the same access violation at address `0x6B` when running
  that file alone (nine tests passed, one failed). This is a pre-existing failure, not a green
  release-native campaign. The existing nullable dynamic-pattern test is the reproducer.

[Validation commands and exit codes](layout-validation.json). Later batches retain the direct
regression boundary and rotate additional coverage, rather than rerunning the whole campaign.
