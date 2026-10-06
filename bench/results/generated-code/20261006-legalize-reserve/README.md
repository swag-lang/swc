# Release legalization without a permanent integer reserve

The interval allocator now uses every admissible integer register. Late legalization
uses the existing short save/restore borrow when concrete liveness leaves no free
register. Operand exclusions remain hard constraints; ordinary concrete liveness is
protected by allocation, rather than copied into permanent virtual prohibitions.
A borrow also checks scratch values already mapped during the current rewrite.
The predictive encoder hook and the second interval-allocation attempt are removed.

## Structural evidence

Both compilers and programs use Release. The baseline compiler contains the sources
of `9c4d457ab`; the candidate starts at `097927c1d` plus this change. The intervening
merge replaces CodeGen payload lookups with existing typed accessors. Compiler hashes,
checksums and every H.264 function group are in `structural-evidence.json`.
No runtime timing improvement is claimed.

| Post-emit cohort | Instructions before / after | Memory operations before / after | RSP memory operations before / after |
| --- | --- | --- | --- |
| LZ77 main | 473 / 465 | 102 / 95 | 28 / 21 |
| SHA-256 main | 359 / 356 | 115 / 107 | 41 / 33 |
| H.264, 334 emitted functions | 44274 / 44078 | 10296 / 10018 | 2538 / 2262 |

Instructions exclude labels. Memory operations exclude address computations and
push/pop. RSP counts include only explicit RSP-relative operands, not every frame
access addressed through another register. H.264 pushes increase from 954 to 1013;
the extra available callee-saved register can require a prologue save.

The LZ77 candidate-search loop no longer transfers its invariant index from XMM2 on
every candidate. SHA-256 loses eight explicit RSP accesses. The accompanying Micro
diffs retain these changes, including their prologue costs.

H.264 uses identical copied module sources with `PrintMicro("post-emit")` on the
14 implementation files under `src/decode/h264`; tests are excluded from this cohort.
Build each compiler with `build --num-cores 6 -bc release --rebuild --module <copy>
--import-api-dir <checkout>/bin/std/.output -n video -od <separate-output>
-wd <separate-output>`, and isolated TEMP/TMP caches. Group by source location and
function name, normalizing generated `__run_expr_<id>` names. The two sides contain
the same 330 groups and 334 function records, including repeated instantiations.
This is a current cohort, not the historical 76-kernel sample in the backlog.

Two H.264 groups gain memory operations: `parsePlaneResidualCabac` (+1) and
`parsePlaneResidualCavlc` (+6). These remain allocation-quality leads; they do not
justify withholding the register from every saturated function. Other changes
include `addPlaneResidual` (-16), `parsePartitionsB` (-13) and `residualCabac` (-11).

## Validation

- Release compiler build; new high-pressure shifts/products fixture.
- Full native suite: 3622 tests, successful intentional recovery probes.
- Release `pixel` and `gui` builds, the two historical reserve-removal blockers.
- Release `video --test-file h264`: 23 tests, JIT and native execution.
- Unchanged official benchmark sources: matching baseline/candidate checksums for
  LZ77 (622942003053), csvagg (24828641), SHA-256 (2503168387), raytrace (56061776).

All compiler commands use six workers and fresh machine-load admission. Validation
uses rebuilt artifacts. Static instruction/register evidence is the acceptance
criterion for this lot, as explicitly requested for the optimization campaign.
