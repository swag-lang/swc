# Static compilation work reductions, 2026-09-14

Work is isolated in `swc-perf-sept14` on `perf/compile-static-sept14`. Each completed
campaign is validated and merged into `master` before the next campaign starts.
Timing measurements are deferred at the owner's request. The work reductions below
are derived from the algorithms; they are not measured compilation-speed claims.

## Campaign 1: control-flow reconstruction and nested JIT metadata

### Static reductions

- Reuse successor and predecessor lists for surviving instruction positions across
  control-flow graph rebuilds. This avoids destroying and constructing every small
  vector and retains overflow capacity for large branches and joins.
- Retain the label-index vector across rebuilds. Reset its entries to the invalid
  sentinel so removed labels never retain an old instruction index.
- Deduplicate indirect-jump destinations from the target's last predecessor. Sources
  are visited monotonically and all edges from one source are appended together.
  Membership therefore takes constant time instead of searching the growing target list.

For the regression fixture's 32 distinct destinations followed by those destinations
in reverse, the old searches perform 496 + 528 = 1,024 target comparisons. The new path
performs 64 constant-time membership checks, with no additional index. Edge discovery
order and duplicate handling are preserved. Reused buffers belong to one MicroBuilder
and are released with its compiled-function state.

`MicroControlFlowGraph_RebuildsLargeBranchesAndRemovedLabels` covers an empty graph,
repeated reconstructions, large incoming and outgoing lists, duplicate destinations,
a removed label, shifted instruction indices, and return to an empty graph.

### Defect found during validation

The native `optimize_constexpr.swg` test failed in `devmode` on the original JIT
preparation path: `#isconstexpr(pureAdd(20, 22))` was false despite optimization being
enabled. The same file failed in isolation. A temporary trace identified unpublished
function relocations reached through `__runtimeAllocator`, a dependency of overflow
reporting. All probe instrumentation was removed.

The stability check follows the entire allocation-relocation graph, but JIT preparation
only followed direct function relocations and one struct-method table. Preparation now
follows every data relocation with an iterative worklist and shared allocation membership.
This includes nested reflection and interface tables, terminates on cycles, and retains
the existing exclusion of ignored functions and generic bodies still being analyzed.
The existing deferred-method reflection tests protect that exclusion.

The original regression passes with the correction. Its optimizer stage still reports
210 functions. Additional proposed reductions passed without the correction and were
removed; the existing native fixture is the demonstrated regression boundary.

### Validation

Candidate build 592, based on `4710bdd4c`, passed:

| Compiler | Program configuration | Boundary | Result |
| --- | --- | --- | --- |
| DevMode | n/a | C++ fast tests | 797 passed |
| DevMode | devmode | Complete JIT suite | 1,410 passed |
| DevMode | devmode | Complete native suite and recovery probes | 3,166 passed |
| DevMode | release | Complete native suite and recovery probes | 3,166 passed |
| Release | devmode | Complete JIT suite | 1,410 passed |
| Release | devmode | Native `optimize_constexpr.swg` | 1 passed |

Both compiler executables built successfully. All compiler commands used six workers;
MSBuild used `/m:6 /p:SwcCompileJobs=6`. Each build or test received a fresh machine-load
admission check. The C++ fast selection excludes filesystem tests. No full repository
campaign or performance benchmark was run.

The final integration incorporates `a0e214fd1` and increments the compiler to build 593.
Both integrated compilers built successfully. The integrated DevMode compiler passed the complete JIT suite (1,410 tests) and native devmode suite (3,166 tests plus recovery probes). The integrated Release compiler passed the native optimize_constexpr.swg regression (one test). Earlier independent C++ and native release evidence remains applicable.
