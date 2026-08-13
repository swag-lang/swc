# Draft — conditional findings, file ONLY if their condition holds at campaign close

Both entries take the next free F identifier at filing time (F-130 as of 2026-08-13 on the
noref branch — re-verify against backlog/README.md AND against master, which is still at
F-129). Advance the F counter with each filing. Replace every <ANGLE-BRACKET> hole with
measured fact; the backlog does not take speculation.

---

## Entry 1 — findings.optimization.md (append at end; keep identifier order)

FILING CONDITION: the end-of-campaign A/B against the master reference compiler (two-binary
protocol: pinned cores, CPU time, alternated runs) shows a regression on element-access-heavy
code attributable to the `opIndexPtr` lowering. If the A/B is flat, this entry is never filed.

### F-13x — Inline `opIndexPtr` element access costs <N>% against the reference world

- Area: compiler/backend
- Found while: the noref campaign's closing A/B against the master reference compiler
  (build of <DATE>), on <BENCH/SUITE>
- Observation: replacing ref-returning `opIndex` with the `opIndexPtr` pair changes the
  generated shape for <PLACE-CONTEXT: member access / assignment target / nested index>:
  <WHAT THE ASM SHOWS — e.g. the inlined pointer round-trips through a frame slot instead of
  folding into the addressing mode, or the value path calls both opIndex and opIndexPtr>.
- Evidence: <MEASUREMENTS: bench name, medians, protocol, and the asm diff of the reduced
  loop — the clang assembly of the equivalent C++ is the answer sheet>.
- Next step: <SMALLEST INVESTIGATION — e.g. check whether the inliner's address result feeds
  the memory operand directly, or reduce to one loop and compare the micro-instruction streams
  of the two worlds>.
- Related: the campaign's decision record — opIndexPtr serves place contexts only, value
  contexts keep `opIndex`; never const-eval.

---

## Entry 2 — findings.compiler.md (append at end; keep identifier order)

FILING CONDITION: the reduced probe below still fails when the campaign closes. The tree
currently MASKS this defect: bin/std/modules/core/src/.../string.swg:301 was rewritten from
`.buffer[0]` to `.buffer![0]` as a doc-conforming workaround, so no suite exercises the broken
path. If the defect is instead fixed on the branch, add the probe as a suite test and do not
file this entry.

### F-13x — A narrowing fact does not survive inlining through a pointer receiver

- Area: compiler
- Found while: the noref campaign's core migration; `String.clear` (`#[Swag.Inline]`) with
  `if .buffer do .buffer[0] = 0` reported "indexing into '#null [*] u8' dereferences a value
  that can still be null" once `me` became a pointer
- Observation: the narrow fact installed by `if .buffer` on a `#null` member is not found by
  the nullable-index query after the method body is cloned into the caller. The same guard in
  a NON-inline `mtd` passes, so the defect is in the inline clone of the guard/usage chain
  through the pointer receiver binding, not in narrowing itself.
- Evidence: probe — `struct S { buf: #null [*] u8 }` with `#[Swag.Inline] mtd clear() { if .buf
  do .buf[0] = 0 }` called from a `#test`: <RESULT AT CLOSE>. The non-inline twin passes
  (campaign probe4). The in-tree workaround is string.swg:301 `.buffer![0]`, which silences the
  diagnostic without restoring the narrowing.
- Next step: trace the clone in SemaInline/SemaClone — what the guard's narrow path resolves to
  on the INSTALL side (condition) versus the QUERY side (`Sema.Index` nullable-index) once the
  receiver is a materialized pointer binding; check `forceRuntimeSafetyMaterialization`
  (SemaInline), which excluded `isReference` receivers and may need the same carve-out for
  pointer receivers. Once fixed, revert string.swg:301 to `.buffer[0]` and keep the probe as a
  suite test.
- Related: the campaign's stage B (me → pointer) decision record.
