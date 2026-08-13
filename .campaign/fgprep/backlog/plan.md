# Stage G bookkeeping plan — noref campaign

Prepared read-only against `c:/Perso/swag-lang/swc-noref` (branch `noref`) on 2026-08-13.
Nothing in the repository was modified. All drafted text destined for the repo is in English
and sits in the companion files of this directory.

---

## 1. Identifier state (verified, with the merge trap)

**On `noref` (`swc-noref/backlog/README.md`, lines 76-77):**

```
Next identifier: F-130
Next identifier: T-386
```

- **F-129 is TAKEN** on `noref`: `backlog/findings.compiler.md:181`, "A constant source through
  a non-ConstExpr implicit opSet in an aggregate literal is lost" (filed by commit `f65690fd3`,
  which also advanced the counter to F-130). It is named only in `findings.compiler.md` and
  `.campaign/NOTES.md` — **no commit message uses F-129**, so it can still be renumbered safely
  if a merge collision forces it.
- **F-130 is NOT taken.** Highest F entry anywhere in `swc-noref/backlog` is F-129. Next
  available F on this branch: **F-130**.
- **T-386 is NOT taken.** Highest T entry is T-385 (`todo.compiler.md:265`). Next available T:
  **T-386**.
- Working tree has no pending backlog edits (only `src/` files and `Version.h` are modified),
  but the build agent is active: **re-grep `^### F-13` / `^### T-38` and re-read the two README
  lines immediately before filing anything.**

**Merge trap — master has diverged:** `c:/Perso/swag-lang/swc/backlog/README.md` still says
`Next identifier: F-129` (T counter agrees at T-386). Consequences at merge time:

- The README counter lines will conflict; resolve by keeping the **higher** of the two counters
  for each kind.
- If master files its own F-129 (or F-13x / T-386+) before `noref` merges, the branch's entries
  collide. Since no commit message names the branch's F-129, renumber the **branch-side** entry
  to the then-next free identifier before merging, and update the one cross-reference in
  `.campaign/NOTES.md` only if NOTES still exists at that point (it should already be deleted —
  see section 3).
- Same rule applies to T-386 if master takes it first: file the ergonomics entry with whatever
  identifier is free at filing time. All drafts below say "T-386" as the best guess of today.

---

## 2. Entries the campaign must leave behind (drafts)

### 2a. T-386 — phase-2 ergonomics (REQUIRED by NOTES stage G)

NOTES stage G: "backlog: T-xxx phase 2 ergonomie (sucre éventuel: lvalue-deref postfix, etc.)".
This is a language-design question open by choice, so it belongs in **`todo.language.md`**, in
that file's discursive house style (not the compact `Intent/Complete when` template — no entry
in that file uses it). Exact text to append: **`draft.todo.language.T-386.md`** (this
directory). Placement: new `## Pointer-model ergonomics` section at the end of the file, after
T-012. Position is priority in a todo file; the user may promote it above the generics section
if the migration friction turns out to dominate daily writing. Advance the T counter to T-387
in the same commit.

### 2b. Perf finding on inline `opIndexPtr` (CONDITIONAL placeholder)

NOTES stage G: "findings F-xxx si régressions perf inline opIndexPtr" — conditional on evidence.
Backlog rules require a reproduction and measurements, so **do not file it speculatively**.
Template with the fields pre-shaped for `findings.optimization.md` house style:
**`draft.findings.placeholders.md`**, entry 1. File it only if the end-of-campaign A/B against
master (two-binary protocol, `reference_ab_benchmark_two_swc_binaries`) shows a regression
attributable to the `opIndexPtr` lowering; otherwise the placeholder dies with the scratchpad.

### 2c. Inline pointer-receiver narrowing gap (CONDITIONAL, discovered by the campaign, currently MASKED)

NOTES records that `string.swg:301` (`if .buffer do .buffer[0] = 0` inside `#[Swag.Inline]`
`clear()`) failed the nullable-index check with `me` as a pointer, that the same guard in a
non-inline `mtd` passes (probe4 green), and that the tree was **worked around** with
`.buffer![0]` — doc-conforming, but it silences the probe instead of fixing the clone path
(SemaInline narrow-guard cloning through the receiver binding;
`forceRuntimeSafetyMaterialization` used to exclude `isReference`). If the underlying defect is
not fixed by the time the campaign closes, it MUST NOT die with NOTES. Template:
**`draft.findings.placeholders.md`**, entry 2 (`findings.compiler.md`). Filing condition: the
reduced probe (struct with `buf: #null [*] u8`, `#[Swag.Inline]` mtd, `if .buf do .buf[0]=0`,
called from `#test`) still fails at campaign end.

### 2d. Existing entries the campaign RESOLVES or STALES (delete/rewrite at stage G)

Backlog rule: when a task resolves or invalidates an entry, delete it or cut it to what remains.

- **`findings.language.md` F-062** ("Struct parameters are always const references, and there is
  no by-value form", line 417) — **DELETE.** The campaign decided and shipped exactly this:
  struct `const&` parameters became by-value with an ABI const-address, zero copy ("Décisions
  arrêtées"). The entry's own next step ("check what the backend already does") is answered, and
  its first evidence link points at `004_008_references.swg`, which stage F deletes — keeping the
  entry leaves a dangling link. If any residue is wanted (an explicit by-value-with-scratch-copy
  spelling), fold it as one line into the T-386 draft instead; the draft already reserves a
  bullet for it.
- **`findings.language.md` F-049** ("`for it in x` binds a live view, never a copy", line 114) —
  **REWRITE OR DELETE.** Its two halves are both overtaken: the documentation half is stage F
  work (`005_003_for_elements.swg` is rewritten — `for &v` = address), and the "invisible live
  view" premise changes now that a struct `for v` binds a **typed, visible** `const *T` and
  writes go through `dref`. Before deciding, confirm with `#typeof` what the final semantics are
  for a **scalar** plain `for v` (copy or view — `for_struct_binding.swg` and Sema.Loop are the
  oracle). If a scalar plain binding is now a copy, delete the entry outright; if any implicit
  aliasing remains, cut the entry down to that residue and refresh its evidence. The residual
  borrow-rule question (invalidation covering an in-place element write read back through the
  binding) moves with whichever half survives, or dies.
- **`findings.safety.md` F-105** (line 101) — **TOUCH UP, do not delete.** It quotes the borrow
  rule's view list "a pointer, a reference, a slice, ..." from `013_004_borrowing.swg:5-8`;
  stage F removes "reference" from that list, so refresh the quotation when the doc edit lands.
  The finding itself (a local stored into a global `any` escapes silently) is untouched by the
  campaign.
- **`todo.language.md` intro, line 8** — the phrase "nullability that does not survive a
  reference" describes an example that no longer parses in the new world. Reword when appending
  T-386 (e.g. "nullability that does not survive an indirection").
- Checked and NOT affected: F-096 (`#move` accepts a plain value — `#move`/MoveReference is
  explicitly kept), F-104 (index binding integer types), F-115, findings.optimization.md
  (no ref-dependent entry), todo.compiler.md T-381/T-382/T-385 (the word "reference" there means
  editor cross-references or MSVC link flags).

---

## 3. End-of-campaign cleanup checklist

Ordered; the first three happen on the branch BEFORE the merge is proposed.

1. **`.campaign/` removal — it is TRACKED.** `git ls-files .campaign/` lists `NOTES.md` plus 10
   probe files (`probe.swg`, `probe2..8.swg`, `probe-ufcs.swg`); they were committed on the
   branch, so removal is `git rm -r .campaign` in a dedicated commit, not a directory delete.
   Also remove the untracked, ignored `.campaign/.output/` (contains `_campaign_test_059e9a61`).
   Before deleting, verify each probe's coverage lives in the suite (mapping from NOTES):
   probe5 → `native/inline/macro_receiver_member_access.swg`; probe6 →
   `native/inline/macro_receiver_indexed_access.swg`; probe7 →
   `native/specops/operator_cast_rvalue_receiver.swg`; probe8 →
   `native/flow/for_struct_member_variadic.swg`; probe/probe2/probe3/probe-ufcs (stage-1
   opIndexPtr/UFCS shapes) → `native/specops/operator_index_ptr.swg` +
   `sema/specops/operator_index_ptr.swg`; **probe4 has NO suite counterpart** — it is the
   non-inline half of the narrowing case of section 2c; when handling 2c, either the fix lands
   with a suite test or the finding is filed, and only then may probe4 be deleted.
2. **`bin/unittests` probes vs suites.** The branch adds 14 unittest files and modifies
   `errors/sema/sema_err_spec_op_signature.swg`; every added file is a deliberate named
   regression suite (`const_eval_pointer_receiver`, `const_eval_pointer_set_receiver`,
   `fallible_wide_result_fail`, `for_struct_member_variadic`, `constant_receiver_address`,
   `inline_rvalue_receiver_lifetime`, `macro_receiver_member_access`,
   `macro_receiver_indexed_access`, `operator_cast_rvalue_receiver`,
   `operator_equals_register_rvalue_receiver`, `operator_index_ptr` x2, `pointer_null_compare`,
   `using_base_receiver_call`) — **keep all of them**; none duplicates another. Stage E will
   delete/rewrite the reference-based suites (NOTES section E list); after stage E, re-run this
   duplication check once on the final diff.
3. **Misplaced `.output` dirs.** The only non-standard one today is `.campaign/.output/` (dies
   with item 1). `bin/{apps,examples,reference,std,unittests}/.output` and
   `bin/unittests/workspace/.output` are the normal workspace outputs — leave them. Re-run
   `find . -name .output -not -path './.git/*'` after stages D-F in case a probe run creates one
   next to a temporary directory.
4. **Scratchpad artifacts (outside the repo).** NOTES names session-scratchpad harnesses:
   `probe-ufcs-ptr`, `probe-me-ptr`, probe9, the `p9m` isolated-module harness, `p26`,
   `boxprobe*.swgs`, and the byte-level sandbox probes ("retirées de l'arbre" — confirmed:
   `find` shows no `probe*` file in the tree outside `.campaign/`). No repo action; the
   scratchpads are session-local and self-expire. The only rule: nothing from them gets
   committed.
5. **In-code leftovers to sweep before merge** (from NOTES, verify each): the enriched
   DEV_MODE assert dump at `CodeGen.Index.cpp:321` (keep only if it is clean diagnostics, not
   campaign instrumentation); the **named-temporary workaround for `defaultSandboxRoot` must NOT
   be committed** (NOTES is explicit: root cause is native drop scheduling of argument
   temporaries — if the workaround is in the tree at merge time, that is a bug to graduate, see
   section 4); any `tryResolveIndexWithArgs` instrumentation from the gui blockage.
6. **Backlog hygiene commit** (section 2d edits + T-386 + counters), then a link check: no
   backlog entry may point into `004_008_references.swg` after stage F deletes it (today only
   F-062 does).
7. **Merge-time counter reconciliation** (section 1): README counters = max(master, noref);
   renumber the branch F-129 only if master consumed it meanwhile.
8. **Version bump discipline** (NOTES G): stage 2 re-bumps to 26 was the plan, but the build
   number has moved far past (BUILD 52 noted); confirm `Version.h` is bumped once more for the
   final merged binary, per "un bump par binaire exécuté".

---

## 4. NOTES triage — what graduates, what dies with `.campaign/`

**Already graduated (nothing to do):**

- Const-set fold hole → **F-129** filed in `findings.compiler.md` (predates the campaign,
  reproduced on master; fix belongs on master).

**Graduates into backlog (file only if still true at campaign close):**

- Phase-2 ergonomics exploration → **T-386** (section 2a, unconditional — NOTES demands it).
- Inline pointer-receiver narrowing clone gap, masked by `.buffer![0]` → F-13x
  (section 2c) — the workaround makes this INVISIBLE to the suites, so it is the single most
  important fact in NOTES that must not die silently.
- Native-only premature drop of argument temporaries (`Path.combine(f().toString(), ...)` —
  the defaultSandboxRoot heisenbug; JIT green, native reads a freed String's slice) → F-13x in
  `findings.compiler.md` if the root cause is not fixed on the branch. NOTES forbids committing
  the naming workaround precisely so this cannot be papered over. Note the possible link to the
  long-open "temporaries never dropped" lead (auto-memory): same scheduling machinery, opposite
  symptom.
- The second memory-fault family ("memory block address is not the start of an allocation"
  after init passes) → same treatment: fix on branch, or file with the repro path.
- The gui codegen assert (`richeditview.swg:217`, IndexExpr reaching codegen without a spec-op
  payload) → should be FIXED before merge (gui green is on the validation ladder); if the
  campaign merges with a workaround instead, file it.
- opIndexPtr inline perf → F-13x ONLY with measurements (section 2b).

**Graduates into documentation / skills (stage F, not backlog):**

- "Décisions arrêtées": opIndexPtr place contexts and never-const-eval; struct params by-value
  with const-address ABI; `&T` removal diagnostics; `#move`/`#fwd` kept — the language
  reference and `write-idiomatic-swag-code` are where these live once NOTES dies.
- `&me` is now `me` (`&me` = address of the slot) — belongs in the pointers reference page and
  the idiomatic-code skill, not in backlog.

**Dies with `.campaign/` (session state, superseded, or already encoded in git/tests):**

- All checkpoint/state sections ("État itération", "Reprise immédiate", "État session", BUILD
  numbers, validation ladders) — git history has the story.
- The three RÉGLÉ crash sagas (macro me-binding, opCast/Set-cast receivers, foreach
  bind-address) — each already left a named suite test and a commit; the prose adds nothing a
  future reader needs.
- The bisection protocol notes (builds 30-34), the oracle-binary pointers, probe-to-fix
  mappings — session tooling.
- The lesson "extending `allowsImplicitAddressBinding` flipped overload ranking and broke 88
  tests" — already encoded as the separate `bindsExplicitMeAddress` predicate; if judged worth
  keeping, it belongs as a comment at that predicate, not in backlog.
