# Compiler allocation lifetimes, 2026-10-29

The compiler now destroys nontrivial objects created in its arenas, releases generic symbol
state, and decommits proximity pages when their data segment, paged store, or JIT manager dies.
The common 2 GiB virtual address reservation remains; freed physical backing is returned to
Windows without reusing addresses that other JIT allocations might still reference.

DevMode also poisons data segments in place at teardown. It keeps the existing stale-pointer
check without allocating a segment-sized temporary buffer. This last change did not demonstrate
an additional reduction in the application process peak; the final figures below include it.

## Measurements

| Workload | Compiler | Before peak working set | Final peak working set | Reduction |
| --- | --- | ---: | ---: | ---: |
| Swag Capture, full rebuild including dependencies | DevMode | 2747.8 MiB | 2453.8 MiB | 10.7% |
| GUI layout tests, full rebuild including dependencies | DevMode | 3575.1 MiB | 2842.3 MiB | 20.5% |
| Swag Capture, same program configuration | Release | Not measured | 1767.0 MiB | Not compared |

These are single uninstrumented runs on frozen consumer sources, with six compiler workers,
`--rebuild`, and separate temporary/cache roots. Windows process counters provide the peak
working set; a fresh job object also records process and process-tree commit. Binary hashes,
source digests, commands, output, and byte counts are in [measurements.json](measurements.json).
The baseline was rebuilt from preserved pre-change C++ sources with profiling symbols, with
heap instrumentation removed. Other work shared the host, so wall times do not establish a
speed improvement, and these samples do not establish a universal memory ceiling.

The application command reproduces the compilation performed by `tools/apps.bat dm build
swagcapture`; it does not launch the application window. Equivalent checkout commands are:

```powershell
bin\swc.dm.exe build --workspace bin/apps --workspace-module swagcapture --num-cores 6 --rebuild
bin\swc.dm.exe test --workspace bin/std --workspace-module gui --test-file layout.test.swg --num-cores 6 --rebuild
```

Both compiled programs use the default `devmode` preset, without `--debug`. The Release row
changes the compiler executable, not the program preset. Its binary contains the same arena and
page-lifetime corrections; the in-place poisoning path is compiled only into DevMode.

## Regression evidence

- Before arena ownership was fixed, the two new compiler resource-lifetime tests failed while
  the existing 1603 source tests passed.
- Before page decommit was fixed, the three new Windows page-lifetime tests failed while the
  other 1607 source tests passed.
- The final DevMode executable passed all 1684 C++ tests with `unittest --dev-full --num-cores 6`.
  The eight new tests cover compiler-owned resources, generic state, arena moves/reset and
  partial construction, three proximity storage owners, and in-place segment filling.
- Swag Capture rebuilt successfully with both compiler executables.
- The final GUI command passed all 32 selected tests.

An intermediate full-suite run could not find a native-root fixture in the isolated resource
tree. The missing fixture was copied into that tree and the final full suite passed. This was
an isolation setup failure, not a compiler failure.

## Scope

The DevMode application build still exceeds 2 GiB. These changes repair missing cleanup and
remove a teardown allocation; they do not meet the wider compiler memory-budget targets.
Test-file filters reduce test execution, not whole-module compilation. Retained compiler state
while a native application is running was not measured by this build-only experiment.

A follow-up experiment mapped newly published cache segments and streamed their payloads
instead of copying them. Application peaks remained near 2.33 GiB, so those cache changes and
their additional test were reverted. The intermediate measurements remain in the JSON with
explicit variant labels; they are not the final implementation.
