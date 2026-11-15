# Form frame addresses in their argument registers

Prompt 2, production baseline `b7bd914f4f`. DevMode GCC 14.2.0 Linux x86-64 compiler;
Release benchmark programs, three workers, forced regeneration and separate installations,
outputs and temporary roots. [Provenance](provenance.json) records both compiler hashes and
native function ranges. Source algorithms, workloads, checksums and build number are unchanged.

A single-use full-width frame address can be formed at its final integer copy instead of
being carried through intervening calls and branches. Existing same-value SSA proofs cover
cross-block bases; local movement keeps the existing clobber checks. Protected argument lanes
remain separate definitions at their original copy positions. Partial copies, SIMD destinations,
changed bases, multiple uses and non-frame roots are excluded. The rule is restricted to
acyclic CFGs: broader loop rematerialization changed carried-register choices and added traffic.

| Linked native function | Instructions before / after | Memory operands before / after | Calls before / after |
| --- | ---: | ---: | ---: |
| `Binarytrees.bottomUp` | 53 / 52 | 20 / 20 | 5 / 5 |
| `Binarytrees.release` | 41 / 40 | 18 / 18 | 5 / 5 |

In both functions the removed instruction is an early address materialization. The later
argument copy becomes the same address materialization directly in RDX. Saved registers,
pushes/pops, frame traffic and allocation/reclamation behavior are unchanged. Both paths
execute once for each of the original workload's 674,478 nodes: this removes 1,348,956 timed
instructions, with checksum `674478`. These are executed-path counts, not a measured speedup.
Full non-debug native functions and their actual ELF stack-trace symbol maps are compressed here.

Java HotSpot is the fastest non-Swag runtime for binarytrees in the accepted Windows campaign
`20261023-175718` (historical median ratio 1.481x). The reusable Linux C2 reference has a
thread-local bump-allocation fast path: at `0x7f118c89d224..0x7f118c89d23f` it reads the top,
adds 24 bytes, compares the limit and publishes the new top. It also inlines recursive levels.
Java does not run a per-node manual release traversal, unlike the Swag/C++ ports. The retained
HotSpot 21 diagnostic, its GC contract and Linux ABI cannot establish the current Windows winner.
This local address-lifetime improvement does not claim to close that runtime/allocator gap.

## Validation and reviewed scope

- 1,703 C++ tests pass. The new pass test covers straight-line and branched calls, changing
  bases, partial copies, protected lanes, multiple uses, non-frame roots, loops and SIMD copies.
- `addressed_register_arguments.swg` passes its JIT and native test in DevMode, covering mixed
  argument widths, several addresses in one call, source-address arguments and iteration.
- All twelve Release benchmark checksums pass the full verbose Micro comparison. Other task
  kernels retain their code. Each emitted `benchFree` loses the same address/copy instruction;
  `__raiseException666` and `__releaseErrRecord` lose an address materialization on their error
  paths, with register renaming and unchanged memory/call counts.
- Atomic overload ordinals swap in the raw comparison; exact body pairing shows no change.
  Generated runtime lambda names and compile-time `__buildCfg` bridge metadata differ between
  compiler installations. The bridge is not linked into the benchmark executables.
- The final restriction leaves allocator, type-comparison, worker-pressure, lock and condition
  loops unchanged. [Raw comparison](microdiff.txt.gz) and
  [all reviewed differences](normalized-diff.txt.gz) retain equal-count changes too.

The pass reuses its bounded movement window and lazy SSA. Frame-base detection adds at most
one linear source scan per round with an eligible candidate; loop eligibility reuses the CFG.
Timing is **not measured**; this batch is **landed, unconfirmed**. A comparable grouped Windows
campaign and corrected run-index comparison are pending a compatible host.

## Rejected alternatives

Restricting cold regions to one call replaced binarytrees' spill traffic with another saved
register. The two extra push/pop instructions ran at every leaf, while only internal nodes
benefited; allocator fallback paths grew too. That trial was reverted. Broad address retargeting
reduced totals but added a memory operand to a worker-pressure loop; heap-root and cyclic-CFG
extensions were removed before retention. Neither trial is included in the retained code.
