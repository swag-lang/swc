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
estimate. With several workers, uncached calls still need clock reads and a pilot iteration; the
cache bounds retained state, and saturation must not force cheap work through the pool on every
call. An already started pool with fewer than two workers bypasses profiling. Moving from one
worker to four also checks that these earlier serial calls do not suppress later adaptation.

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

These measurements predate the direct path for an already started serial pool. That path now
avoids the profile lookup, pilot iteration and clock reads with fewer than two workers. Checking
the existing pool adds work to the multi-worker path; repeat both controls on a quiet machine
before claiming an overall speedup. The scheduler startup test also reuses a parallel body while
four host callers grow the pool, checking every result across the serial-to-parallel transition.

A follow-up on the same date compared the serial bypass and moving partition storage into a
private, non-inlined dispatch function. CPU load at admission was 3%, 4% and 4% for the three
variants below, respectively:

| Runtime | One worker, median us | Four workers, median us |
| --- | --- | --- |
| Serial bypass; partition storage in the entry frame | 300 | 806 |
| Serial bypass disabled; partition storage in the entry frame | 682 | 679 |
| Serial bypass; partition storage in a separate dispatch frame | 354 | 844 |

These short runs establish no uniform time improvement. The serial bypass helps the one-worker
control and adds a pool observation to the multi-worker control. Outlining the dispatch reduces
stack use: the Release micro dump reserves `0xE0` (224) bytes in `__parallelRange`, down from
`0x1F28` (7,976), excluding saved registers and outgoing call arguments. The large partition
array now belongs to `dispatchParallelRange`, which is entered only when dispatch is needed.
The native `parallel_for_stack.swg` regression checks that seventeen nested single-iteration
loops stay within a 64 KiB stack budget; the previous runtime fails that assertion. JIT execution
does not exercise this native stack measurement.
