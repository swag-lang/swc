# mimalloc 3.6.0 integration, 2026-10-30

The compiler now embeds upstream mimalloc 3.6.0 instead of 3.4.3. The import removes
the old local patches: upstream now supports 16 KiB page commitment and the corrected
commitment comparison. Its Windows desktop implementation already links `advapi32`.
DevMode retains `MI_DEBUG=3` and `MI_SECURE=3`.

This update is not a memory reduction. The two application pairs both use more memory
with 3.6.0; the GUI difference is small. Further compiler memory work remains necessary.

## Observations

| Workload | Compiler | 3.4.3 peak working set | 3.6.0 peak working set |
| --- | --- | ---: | ---: |
| Swag Capture rebuild, first pair | DevMode | 2461.2 MiB | 2554.7 MiB |
| Swag Capture rebuild, repeated pair | DevMode | 2456.6 MiB | 2602.4 MiB |
| GUI layout tests | DevMode | 2845.4 MiB | 2870.2 MiB |
| Swag Capture rebuild | Release | Not measured | 1824.7 MiB |
| GUI layout tests | Release | Not measured | 2169.9 MiB |

These are observations on a shared host, not a statistical performance campaign. The repeated
application pair took 83.05 s with 3.4.3 and 83.31 s with 3.6.0; process CPU time was 390.98 s
and 387.95 s. The first pair had substantially different timing. These samples do not establish
a speed improvement or slowdown.

All runs use six workers, `--rebuild`, the default program `devmode` preset without `--debug`,
and separate temporary/cache roots. The frozen runtime, standard library and application sources
were checked byte for byte against the base checkout. Workspace output directories are shared
between sequential runs and rebuilt. Generated token/function counts vary slightly between some
runs; raw output is retained. Windows process counters supply the peak working set; a fresh job
object records committed memory. Commands, binary hashes, source digest and byte counts are in
[measurements.json](measurements.json).

Equivalent consumer commands are:

```powershell
bin\swc.dm.exe build --workspace bin/apps --workspace-module swagcapture --num-cores 6 --rebuild
bin\swc.dm.exe test --workspace bin/std --workspace-module gui --test-file layout.test.swg --num-cores 6 --rebuild
```

## Validation

- Both DevMode and Release compiler builds passed.
- The DevMode compiler passed all 1685 C++ tests with `unittest --dev-full --num-cores 6`.
- The new allocator test covers zero-size and over-aligned allocations whose allocating
  thread exits before another thread checks and frees them.
- Both compiler executables rebuilt Swag Capture and passed the 32 GUI layout tests.
- All 219 vendored files match the official 3.6.0 archive after normalizing line endings;
  generated `docs/` output is omitted, as in the previous import.
- Whitespace checks pass for the integration code. Five upstream Markdown files retain
  upstream's extra blank line at EOF.

Initial C++ harness attempts stopped on PowerShell stderr handling and then an unsupported
`--rebuild` argument. The corrected invocation completed successfully; these were harness errors.
