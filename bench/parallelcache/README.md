# Parallel-loop cache pressure

```powershell
bin/swc.dm.exe run -f src/parallelcache.swg --module-file bench/parallelcache/module.swg -bc release --num-cores 6
```

The benchmark calls 512 distinct `parallel for` bodies, each with three cheap iterations. A
balanced generic specialization tree creates the bodies without generated source files. Each
body writes a different constant and destination, preventing identical-code folding from merging
their entry points. This exceeds the runtime's fixed 256-entry cost table even with four-slot
probing.

Each sample warms every body once, then times 16,384 calls. All 1,536 destination values are
checked outside the timed region, with assertions enabled in the Release program. Three samples
run with one worker, followed by three with four workers; the pool never needs to shrink.

The useful comparison is the additional cost of four workers when some bodies cannot keep an
estimate. Uncached calls still need clock reads and a pilot iteration; the cache bounds retained
state, and saturation must not force cheap work through the pool on every call.

Build separately when preparing a timing run, then use the same `run` command above:

```powershell
bin/swc.dm.exe build -f src/parallelcache.swg --module-file bench/parallelcache/module.swg -bc release --num-cores 6
```

Admit every build and run with the repository's machine-load check. Use a quiet machine for
timing comparisons; the benchmark does not assert a duration or a portable speedup.

On 2026-09-08, the same benchmark and DevMode compiler built a Release program first with the
previous single-slot lookup, then with bounded probing and uncached cost sampling:

| Runtime | One worker, median us | Four workers, median us |
| --- | --- | --- |
| Single-slot lookup; collisions dispatch normally | 929 | 52592 |
| Four-slot lookup; uncached calls sample locally | 1759 | 1627 |

CPU load at admission was 23% before and 14% after; these are indicative measurements on a shared
machine. The large worker penalty disappears in this deliberately saturated case. The extra
clock reads and estimation on uncached calls also raise the one-worker cost, so this is not a
claim that every workload gets faster. Neither version allocates storage for more cached bodies.
