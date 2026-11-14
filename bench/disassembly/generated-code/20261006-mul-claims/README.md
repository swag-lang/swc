# Output-only multiplication claims: structural improvement

The candidate gives `OpBinaryRegReg` and `OpBinaryRegMem` the existing
`RegisterDefsAtOutput` flag. A definition-only RDX claim then starts at MUL's output
slot, allowing a dying operand in RDX. Read/write RAX, division's RDX and shift
counts retain their input constraints. The exact experiment is in `experiment.patch`.

Baseline: `f1de4adbd`. Candidate: that revision plus the patch. Both compiler builds
and all generated programs use Release. Benchmark inputs and timing boundaries are
unchanged; setup remains outside the measured kernel. Compiler time was not measured.

The unsigned `/ 7`, signed `/ 11` and carried-input probes return the same values;
their final Micro streams keep the same instruction counts and use RDX instead of
R8/R9 for the multiplier. The 275 native optimizer regressions pass. Csvagg's text
shrinks by 64 bytes and its allocation changes, including untimed input generation.
This static difference does not establish a runtime benefit.

The first window uses 15 accepted, alternating baseline/candidate pairs per task,
plus unchanged-baseline controls, process isolation, CPU-0 affinity, and one warmup
per version. Background CPU above 15% rejects a sample. The declared useful-gain and
non-regression threshold was 3%, with a maximum of 30 attempts per task. All samples,
including rejected ones, executable/compiler hashes and commands are retained in
`release-samples.json`. Checksums agree throughout.

| Task | Median paired candidate/baseline change | Median paired control/baseline change |
| --- | ---: | ---: |
| csvagg | +1.37% | +0.29% |
| lz77 | +1.39% | -0.95% |
| dijkstra | -1.14% | -2.68% |
| fannkuch | +5.16% | -2.55% |

No target runtime gain was established, and fannkuch gives an adverse signal.
No second window was spent attributing that signal. The user explicitly accepts a
proven structural optimization without a measurable speedup on this shared machine.
The change is therefore retained for its shorter fixed-register claim and reduced
register pressure, not as a timed win. The observed fannkuch/layout interaction
remains a separate investigation; correctness tests do not explain timing differences.

The permanent Release regression covers signed and unsigned constant quotients,
32/64-bit boundaries and operands retained across two multiply-high sequences.
These samples are not a full campaign and do not update benchmark history.
