# Runtime/API archive index

The reader searches the sorted mapped keys directly and retains a four-byte body
offset per record. It no longer allocates an owned key and hash node for every
archived record at process startup. New writes take precedence in a pending map;
publication still merges generations under the existing directory lock. The
archive format, compiler version and body checksum contract are unchanged.

## Controlled comparison

Both Release executables were linked from the same snapshot of 456 common object
files; only `CompilerCacheStore.obj` differs. The baseline object uses the original
reader and its original header, with its include redirected to the external copy.
Both links use the same options. [Build identities](comparison-build.json) retain
the executable and object hashes. The candidate grows by 2,560 bytes.

Both executables use the same frozen runtime, generated API files and devmode native
dependencies, recorded in the [resource manifest](resources.json). Benchmarks use
six workers, new native output directories, private caches, a 15% CPU admission
ceiling and the full repository memory thresholds before every invocation. No
build or test from this task overlaps the timed comparisons. Other sessions can
start work after admission; the samples retain that shared-machine variability.
Population and reuse pilots precede alternating A/B and B/A pairs. Pilot programs
execute separately and print `42`. Timings include cache loading, fingerprinting,
any new variant emission, publication and shutdown.

## Ordinary consumer archives

[All samples](consumers.json) contain five pairs per consumer. The ratio is the
median of candidate/baseline times within each pair; it need not equal the ratio
of the two independent medians.

| Consumer | Baseline median ms | Candidate median ms | Paired wall ratio |
| --- | ---: | ---: | ---: |
| runtime | 160.79 | 153.67 | 0.9725 |
| core | 311.02 | 305.85 | 1.0805 |
| pixel | 316.47 | 325.57 | 1.0287 |
| gui | 589.93 | 595.43 | 1.0109 |

These samples establish no consistent whole-command gain on the small ordinary
archives. In particular, the Core paired wall ratio is above one and its first
pairs differ substantially during source analysis, before the affected backend
cache path. The runtime candidate also has a 557 ms outlier. These data do not
certify either an improvement or a stable regression for these consumers.

## Crowded archive

[All nine pairs](occupied.json) compile the same runtime consumer after seeding
50,000 unused records in each archive outside the timer. Dummy keys are zero-padded
hexadecimal integers and dummy bodies hold one byte. This measures index occupancy
and whole-command publication cost, not production or loading of 50,000 real
functions. Real keys and bodies are preserved. Conservative fingerprint misses
can still publish new variants; these are warm builds, not guaranteed all-hit
lookups.

- Whole-command median: 200.50 ms to 182.29 ms.
- Median paired wall ratio: 0.8979, about 10.2% lower; seven of nine pairs improve.
- Median paired CPU ratio: 0.8696, about 13.0% lower.
- Median peak job memory: 92.35 MiB to 82.32 MiB; paired memory ratio 0.8984.

The two faster baseline outliers remain in the comparison. These results support
the crowded-archive case only; they are not a speedup claim for normal module
graphs. Reproduce with frozen compilers and matching resources beside them:

```powershell
py -3 -B bench/parsecache.py --scratch C:\external\results --against C:\external\baseline\swc.exe --compiler C:\external\candidate\swc.exe --only runtime --unused-records 50000 --reps 9 --max-cpu 15
```

## Validation

- DevMode and Release compiler builds passed with MSBuild `/m:6` and `/MP6`.
- The DevMode C++ suite passed all 1,600 tests.
- The repository backlog and link audit passed.
- [DevMode](verification-devmode.json) and [Release](verification-release.json)
 cache consumers passed native and JIT calls, changed API bodies/literals and
 callee effects, current consumer globals, program configurations and compiler
 identity, diagnostics, corruption repair, forced rebuild with mapped readers,
 statistics bypass and concurrent publication.
- Both runs also passed the new 8,192-unused-record index case and complete rejection
 and repair for duplicate/unsorted keys, excessive counts, empty/overrunning bodies
 and trailing bytes. Each repaired archive was reused on the next invocation.
- The seeding helper preserves every real key/body and is byte-idempotent on repeated
 calls; [checks](seed-tool-check.json) retain that result.
- The maintained driver's `--unused-records 7` branch passed population, native
  execution, reuse and one timed pair; [smoke results](seeded-tool-smoke.json) are
  tool validation only, not another performance series.

Publication still materializes existing keys when it merges a delta; the unresolved
work is tracked in `compiler.core.086`. Source loading, lexing, parsing, semantic
analysis and initial IR generation remain outside this change.
