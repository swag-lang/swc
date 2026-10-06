# Campaign Prompts

Seven long-running campaigns, one prompt each, ready to copy into a fresh session. They are not
tasks: each one is a target that takes many rounds to reach, and each prompt is written to keep an
agent working through the rounds instead of stopping at the first thing that does not work.

Each prompt names the goal, the evidence to collect, the loop to run, the rules that must not be
broken, and — most importantly — the condition under which the campaign is allowed to end.
Prompts 2 through 7 use the shared working protocol below; copy-pasting one of them into a fresh
session works because it explicitly points back to that protocol. Every number quoted below was
measured on this tree and is reproducible with the command next to it.
Re-measure historical numbers when the campaign needs them; use a fresh source inventory for
code-quality campaigns.

| Campaign | Target |
| --- | --- |
| [1. Repository health reset](#1-repository-health-reset) | Restore a clean, current, all-green baseline |
| [2. Generated-code performance](#2-generated-code-performance) | Reach the fastest other language on each `bench/` task |
| [3. Safety without annotations](#3-safety-without-annotations) | Rust-class guarantees with nothing for the user to write |
| [4. Compilation speed](#4-compilation-speed) | The fastest thing that does this work |
| [5. Compiler memory](#5-compiler-memory) | A fraction of the resident set, at the same speed |
| [6. Compiler code health](#6-compiler-code-health) | Apply risk-free mechanical cleanup to swc itself |
| [7. Swag code and API quality](#7-swag-code-and-api-quality) | Make all of `bin/` an exemplary showcase of idiomatic Swag |

Campaigns 4 and 5 constrain each other on purpose: speed must not cost memory, and memory must not
cost speed. They may run concurrently in separate worktrees; campaign 5 and the dedicated benchmark
campaign measure both numbers before claiming a quantitative win.
Campaign 4 changes compiler work to reduce compilation time; campaign 6 improves the compiler's
source without changing that work. Assign an idea by its intended result: a faster compiler belongs
to 4, while a mechanically equivalent cleanup belongs to 6, even when both touch the same file.

### Shared working protocol (prompts 2–7)

Read and follow this entire protocol for any of prompts 2 through 7. Give each campaign its own
branch and worktree outside the main checkout, from the current `master` commit. Use a unique branch
name and path when another agent may already run the same campaign. Keep its compiler binary and
build outputs in that worktree. Use its checkout-local compiler, not a binary from another tree.
Prefix every campaign commit, including integration commits, with `[prompt N]` for its prompt
number. Never edit another agent's uncommitted files or worktree.

Start from the relevant existing evidence and make the first useful edit promptly. Do not open a
campaign with a full baseline build, full test sequence, whole-tree sweep, or complete benchmark.
Run a starting command only when it is needed to reproduce a specific failure or answer the next
implementation question. Historical results guide selection; record a fresh baseline alongside a
later comparison only when that comparison is needed.

Work in coherent code batches. A batch may contain several related edits and local inspections;
do not rebuild or retest after each edit or failed hypothesis. Inspect the diff and complete the
batch, then build only the executable needed for that behavior, if one changed, and run the
smallest focused check that can catch its regression. Rebuild sooner only when the next edit
depends on current compiler output, generated code, a crash, or a diagnostic. Reverted trials need
no validation. Follow validate-swag-changes and machine-load admission for every build or test.

Commit each retained, focused-validated batch in its worktree. Integrate the first validated code
batch into local `master` promptly, then integrate coherent groups at most every four to six
retained batches and before ending a work session with a validated gain. Include required tests and
documentation with the code. Bring the worktree up to date with concurrent `master` changes,
resolve conflicts, and rerun only checks invalidated by the integration. Keep routine observations
in the final report and update backlog at useful milestones; never merge a notes-only batch.

Rotate an unrelated focused check every few retained batches when it exercises a meaningful path.
Run broad suites, cross-configuration checks, whole-tree sweeps, and full measurements about every
five retained batches, after a change whose risk specifically calls for them, and before a final
claim that depends on them. They are not gates for every low-risk batch or intermediate merge. A
focused failure must be reduced and fixed before retention; do not carry a known regression into
`master`.
When optional validation or measurement is delayed by machine load, continue source investigation
or the next independent edit instead of waiting through repeated admission rounds.

Keep `SWC_BUILD_NUM` unchanged for ordinary compiler changes. Isolate or clear affected caches
when an older binary's artifacts would make validation unsafe. Keep temporary logs and probes
outside the checkout, and use the checkout-local compiler with the repository worker cap.

Several agents may run different campaigns at once.
Before each integration, inspect current `master`, incorporate its committed changes into the
campaign branch, and rerun the focused checks affected by the combined code. A new `master` commit
may change the behavior being tested; checks run against the combined revision provide additional
cross-campaign coverage. Do not treat a prior green test on an older revision as evidence for a
later combined revision when its inputs changed. Admit concurrent builds and tests separately from
measured machine load; isolated worktrees do not isolate CPU or memory.

Fix every concrete defect, failing test, regression, broken consumer, or incorrect contract found
during the campaign, regardless of which prompt or agent introduced it. Reduce it, repair its root
cause in the discovering campaign's worktree, add focused regression coverage, and integrate the
repair into `master` promptly. If another agent already integrated the same repair, incorporate it
and verify the affected check instead of duplicating the change. Tell the other agent which
cross-campaign failure was found and which commit fixes it when communication is available. Do not
mark a defect as pre-existing, unrelated, outside campaign scope, or merely record it in backlog
or the final report. A failed optimization idea with no defect can simply be reverted. A genuine
external blocker must be described precisely; it does not make the campaign complete. Campaign
specific restrictions on planned improvements do not prevent a focused defect repair, including
the compiler executable and tests needed to validate that repair.

Campaign 1 runs directly on `master`. Campaigns 2 through 7 follow the shared protocol in separate
worktrees. A shared tree picks up foreign uncommitted edits, and MSBuild can then link another
agent's in-flight code into the binary being validated.

---

## 1. Repository health reset

```
Prefix every commit message for this campaign, including worktree and merge commits, with [prompt 1].

Keep commits tied to verified repairs. Record routine observations in the final report; consolidate
required backlog and documentation corrections at useful milestones instead of committing each note.
Keep `SWC_BUILD_NUM` at its current value during ordinary source changes; isolate or clear affected
caches when changed compiler behavior would make an older binary's artifacts unsafe to reuse.

You are running a repository-wide health reset on swc. The primary goal is to verify the code,
find bugs by executing the complete validation campaigns, and fix them. Documentation and backlog
accuracy are required secondary outcomes; they must never delay the first complete code campaign.

Read AGENTS.md, modify-swag-codebase, validate-swag-changes, and the README/tool instructions needed
to start the builds and tests. Read each additional skill when the work enters its scope. Do not
read every backlog domain, audit every document, or normalize prose before starting validation.

This is not an audit that ends with a list of problems. You own every concrete problem this pass
exposes, wherever it lives: compiler, language, runtime, standard library, application, example,
test, tool, documentation, formatting, packaging, or repository hygiene. Find its root cause, fix
it, add the regression protection it was missing, and rerun the affected campaign. "Pre-existing",
"unrelated", "flaky", and "outside the original scope" describe where a defect came from; none is
a reason to leave it behind.

WORK DIRECTLY ON MASTER

Run this campaign in the main checkout on `master`, not in a separate worktree. Before changing
anything, confirm that `master` is checked out and that the working tree contains no unexplained
local change. Preserve any intentional pre-existing change and include it in the recorded starting
state; never reset or overwrite it merely to make the campaign start clean.

Use the main checkout's compiler explicitly for every repository tool, for example
`bin\swc.exe tools\tests.swgs`; never use an unrelated `swc` found on PATH. Compiler builds and test
runs launched by AI agents, including Codex and Claude, share the machine with every worktree,
IDE build, and user command. Follow the CPU and memory admission rules in modify-swag-codebase
before every build and test command, and cap compiler workers at six. Never terminate or interfere
with another session's processes to create headroom.

Record the starting commit, `git status --short --branch`, toolchain versions, and the available
external prerequisites before changing anything. A starting failure is useful attribution, but it
is not an exemption: this campaign fixes baseline failures too.

CLEAR ALL SWAG BUILD STATE FIRST

Immediately after recording that starting state, and before inventorying, formatting, generating,
building, or testing anything, remove every Swag compilation artifact from every workspace. Use
the checkout-local compiler's `clean --workspace` command for each workspace so all `.dep`, `.tmp`,
and `.output` trees are removed, then run `bin\swc.exe clean --cache` to clear every dependency copy
created by scripts, including the legacy script cache. Preview and verify the exact targets first,
following the repository's destructive-action rules; do not substitute a broad `git clean` or an
unscoped recursive deletion. Confirm that the targeted workspace artifacts and script caches are
absent before continuing. This initial reset is mandatory even when the tree appears clean, and is
separate from the final repository-hygiene pass.

GOAL

Leave one reproducible baseline from which new work can start without inheriting noise or doubt:

  - DevMode and Release compilers build from source.
  - Every canonical build, test, integration, smoke, and packaging campaign listed below is green.
  - Every project-owned Swag and C++ source is canonically formatted, and a second formatting pass
    changes nothing.
  - Generated documentation and website assets are current, reviewed, and reproducible; a second
    generation changes nothing.
  - A complete benchmark campaign passes from a cold Swag build state near the end of the reset,
    with valid checksums, accepted measurements, and regenerated history and report.
  - Every backlog entry is truthful, current, uniquely identified by its owning file, correctly
    linked, and stored in the right domain. Resolved or invalid entries are gone.
  - Inline TODO, FIXME, HACK, and XXX markers have either been resolved or moved into a properly
    evidenced backlog entry; stale comments and dead instructions are gone.
  - Temporary files, misplaced output folders, abandoned snapshots, crash residue, and editor or
    tool noise are gone without deleting intentional fixtures or canonical output roots.
  - The intended fixes are committed in coherent changes, `git diff --check` is clean, and
    `git status --short` is empty at the final commit.

This does not mean implementing every backlog item. Deliberate future intent and unresolved leads
may remain. It does mean fixing every actual defect, inconsistency, stale statement, broken link,
failing command, formatting drift, and hygiene problem discovered by this pass. Rewording a
concrete failure as an investigation is not a way to make the campaign appear green.

EXECUTION PRIORITY: RUN CODE FIRST

After the starting-state record and mandatory artifact reset, immediately start validation steps
1 through 7. Stop at the first failure, reduce it, fix its cause, add its regression, and rerun
the affected campaign. An already failing test always takes priority over documentation wording,
backlog ordering, historical identifier research, or a general API/prose review.

Mechanical preflight checks may block a test launch. Fix only the blocking invariant, then resume
the tests; do not turn that interruption into a full documentation audit. Update documentation
needed to make a code fix correct, but defer unrelated editorial cleanup until the code campaign
has passed. Report executed suites, test counts, failures, and fixes as the main progress evidence.

Use parallel work when available: keep the primary agent on code validation and failure diagnosis,
and delegate bounded backlog/documentation audits. A secondary audit may advance while tests run,
but it must not hold up the next validation command. Coordinate file ownership: collect proposed
documentation/backlog edits separately while a running campaign reads those inputs, then apply
them at a safe boundary. Do not change test inputs underneath a running suite.

Parallel agents do not make build outputs independent. Never overlap cleanup or rebuilding with
another command using the same artifact or dependency paths. Serialize such commands unless all
shared outputs are actually isolated, and admit every build/test from measured machine load.

After the code campaign is green, finish the secondary audit, canonical formatting, documentation
generation, and the final backlog pass. Any newly exposed code failure immediately regains
priority. Complete affected reruns, review, cleanup, and commits before the final Vault integration.

RUN THE COMPLETE VALIDATION LADDER

Run steps 1 through 7 first, in order, stopping at the first failure as the tooling requires.
Steps 8 and 9 remain deferred until the secondary audit and final cleanup are complete. After any fix, rerun the
smallest focused reproducer first, then restart the smallest aggregate campaign that contains it.
Resume the ladder at the earliest step the fix can actually affect; keep earlier independent green
steps valid. A stale golden, fixture, generated asset, packaging input, or similarly local data
change does not invalidate compiler builds or unrelated workspace campaigns merely because it was
committed later. Restart the ladder from the beginning only when the fix changes a shared compiler,
runtime, standard-library, repository-tooling, or build input that earlier steps consumed, or when
the impact cannot be bounded confidently. Record the invalidation decision in the live campaign
table so both a full restart and a narrow resume have explicit evidence:

  1. Rebuild `swc.dm.exe` with the DevMode solution configuration using MSBuild `/t:Rebuild`
     to establish the initial baseline from freshly compiled C++ objects.
  2. `bin\swc.exe tools\build.swgs dm --all-cfg` - build every workspace in release and devmode,
     including modules that have no tests.
  3. `bin\swc.exe tools\tests.swgs dm` - the full DevMode default campaign.
  4. `bin\swc.exe tools\tests.swgs dm --all-cfg` - the same four-rung headless campaign in both target
     configurations.
     Then run `bin\swc.exe tools\integrations.swgs dm --all-cfg`: the named OpenGL renderer,
     Windows host-window, and real-program smoke campaigns in both target configurations. These
     integrations require an interactive desktop and remain outside the headless test set. Later
     renderer and host campaigns belong here under their own tags and names.
  5. Rebuild `swc.exe` with the Release solution configuration using MSBuild `/t:Rebuild`
     to establish the initial baseline from freshly compiled C++ objects.
  6. `bin\swc.exe tools\tests.swgs` - the full Release validation campaign. Do not add a Release
     `--all-cfg` pass; the repository workflow deliberately reserves all-config coverage for
     DevMode.
     Then run `bin\swc.exe tools\integrations.swgs` with the Release compiler for the OpenGL,
     current-host window, and smoke campaigns in the default target configuration.
  7. `bin\swc.exe tools\vsix.swgs` - refresh and package the VSCode extension with its documented
     Node.js/vsce prerequisites, then inspect the package result.
  8. Run the complete cold-start benchmark described below, after all non-privileged repairs,
     affected reruns, formatting, documentation generation, cleanup, and source commits.
  9. LAST: run `bin\swc.exe tools\vault.swgs dm` with the bundled signed WinFsp runtime and the
     required Windows elevation (UAC); no prior machine-wide WinFsp installation is required.
     This integration is intentionally outside tests.swgs and is part of a genuinely full pass.
     Start it only after steps 1 through 8, all fixes and affected reruns, the final backlog and
     documentation reviews, repository cleanup, and commits are complete. Do not trigger its
     elevation prompt or any privileged WinFsp setup earlier or in parallel: the secure desktop
     can block the user's computer, so Swag Vault must be the last remaining work.

Do not silently skip a campaign because a prerequisite is absent. Install or arrange an in-scope
prerequisite when authorized. If external privilege, hardware, software, or authority genuinely
cannot be obtained, keep working through every independent item, report that command as an explicit
blocker, and do not describe the overall baseline as fully green.

FIX, DO NOT EXPLAIN AWAY

For every failure or suspicious result:

  1. Reduce it to the smallest reproducer and identify the root cause.
  2. Fix the owning subsystem, even when it is different from the subsystem that exposed it.
  3. Add a test at the real boundary. For compiler regressions exposed downstream, add the required
     `bin/unittests` suite case before relying on the downstream test alone.
  4. Update affected documentation, reference prose, examples, public API comments, backlog entries,
     and tooling maps in the same fix.
  5. Rerun the focused test, its all-configuration coverage where applicable, and then the aggregate
     campaign that found it.

A rerun that happens to pass does not close a flaky failure. Find and fix its nondeterminism. Do not
disable a test, weaken an assertion, broaden a timeout, accept a crash, update a golden blindly,
narrow a safety check until it stops firing, or add a local workaround. A golden changes only after
the new output has been independently reviewed and proved correct.

COMPLETE THE SECONDARY REPOSITORY AND DOCUMENTATION AUDIT

This work follows the code-validation priority above. It may run in parallel through a separate
agent, but the primary agent must not wait for it before launching or advancing the code campaign.
Read backlog/README.md and every inventoried domain when starting this phase, then:

  1. Inspect tracked, untracked, and ignored state. Use `git clean -ndX` only as a preview; never
     run a broad clean command without classifying its exact targets first.
  2. Search project-owned files for TODO, FIXME, HACK, XXX, disabled tests, unconditional skips,
     suspicious expected failures, stale `.actual.txt`/`.actual.png` snapshots, crash dumps, and
     scratch names. Exclude vendored sources and generated outputs from conclusions, not from the
     initial inventory.
  3. Rebuild the backlog from repository reality, file by file; do not merely proofread its prose
     or assume a recently edited entry is current. Verify every claim against the current
     implementation, tests, documentation, and relevant Git history. Delete shipped or invalid
     outcomes even when their entry contains useful history; history belongs in Git. Cut a partly
     completed entry down to one independently finishable result, split unrelated remaining
     results under fresh identifiers, move work to the domain that owns it, refresh evidence,
     acceptance conditions, and next actions, merge duplicates, and stamp each refreshed entry so
     it rises to the top of its file.
     When investigation establishes implementation work, update the same entry in place and retain
     its identifier. A move to another domain is the exception: allocate that file's next suffix and
     update every live reference and Markdown fragment. Audit files with no recent commit too, and
     delete empty category files rather than treating their existence as coverage.
  4. Check backlog invariants mechanically: every domain file follows `<family>.<what>.md`; every
     entry identifier is that file name without `.md` plus a three-digit suffix; live identifiers
     are unique; a new suffix is one above the greatest suffix ever allocated in that file; every
     entry opens with its `Recorded` stamp and any `Updated` stamp under it is no earlier and says
     what changed; and the README inventory carries each file's latest stamp, newest first.
     Compare with Git history when needed to prove that a deleted suffix was not reused. Check valid
     Markdown anchors and file links, no dangling live cross-reference, and no domain file missing
     from the README inventory. The README is an index and naming contract, not a counter registry.
     A `Related:` line names live entries only; a retired identifier may remain solely as explicit
     historical provenance. Sort each file by `Updated`, or by `Recorded` when there is no
     `Updated` stamp, from newest to oldest. Neither identifiers nor judged value decide position,
     and no `##` heading groups the entries. Read new stamps from the clock when writing them;
     preserve existing `Recorded` stamps when updating an entry.
  5. Check the portability exception explicitly: every operating-system backend, product port,
     target integration, and Windows-bound contract that must become portable lives in
     `backlog/platform.portability.md`, with none of that work scattered through owner-domain files.
  6. Check repository instructions, READMEs, public API documentation, the language reference,
     examples, command help, and website prose against the code that exists now. Update every stale
     command, count, name, guarantee, prerequisite, or link you find.

If an invariant can regress silently and no automated check protects it, add the smallest useful
check to the repository tooling or tests. The next health reset should not need to rediscover the
same class of problem manually.

Repeat the complete backlog pass after the last source, test, or documentation fix. A health
reset changes the facts the backlog describes, so an audit performed only at the start is stale by
construction. In the live campaign table, record every backlog entry removed, narrowed, split,
moved, or refreshed, plus the code/test evidence used to keep every entry that remains.

FORMAT AND REGENERATE, THEN REVIEW THE DIFF

After the complete code campaign is green, finish formatting and generation. These are validation
steps too: fix any code defect they expose, run its focused reproducer, and rerun only the affected
aggregate before returning to the secondary audit:

  1. Format every Swag workspace with `bin\swc.exe tools\format.swgs dm`.
  2. Format every project-owned compiler `.cpp`, `.h`, and `.inc` file under `src/` with
     clang-format and the repository `.clang-format`. Exclude vendored mimalloc sources; do not
     rewrite third-party code.
  3. Run both formatters a second time and prove that the second pass introduces no additional
     change. Review the complete formatting diff; formatting is not permission to hide a semantic
     change or rewrite unrelated generated/vendor files.
  4. Regenerate the complete documentation site and brand assets with
     `bin\swc.exe tools\help.swgs dm`. Review every tracked change for correctness, including public
     API pages, the executable language reference, links, images, indexes, and examples.
  5. Run the documentation generation a second time and prove it is idempotent. Fix the generator
     if it is not; do not normalize nondeterministic output as expected churn.

When formatting or documentation exposes a compiler or tool defect, fix that defect at the root
and add its regression test. Never hand-edit generated output to make the diff look right.

RUN THE FINAL BENCHMARK FROM A COLD BUILD STATE

The benchmark is required on every health reset. A crash or failed benchmark is a code failure:
reduce it, repair its cause, add focused coverage, and repeat the complete benchmark after the
affected validation. A quick smoke or report-only invocation does not satisfy this step.

After the cleanup below and the final source commits, preview and verify the exact generated
targets, then clear the benchmark's generated build outputs, the Swag workspace artifacts it
consumes through `clean --workspace`, and the script dependency cache through `clean --cache`.
Preserve benchmark sources, recorded campaigns, history, and reports. Confirm the selected build
state is absent before launching; never clear another session's live artifacts.

Use the freshly validated Release compiler without rebuilding it inside the measurement command:
`bin\swc.exe --num-cores 6 tools\bench.swgs --no-build --swc-cores 6 --label "prompt 1 cold baseline"`.
Wait for machine-load admission and the harness's quiet-machine gate. Run no other build, test,
generation, or audit workload during the measurements. Cold means no reused Swag build artifacts
at campaign entry; retain the harness's calibration, warm-up, per-sample preparation, checksum,
and noise-rejection rules so the result remains comparable with history.

Review the campaign's checksums, errors, acceptance status, history, and generated report. Record
the measured commit, compiler identity, worker cap, cleared targets, campaign identifier, and
result in the live table. Commit the accepted benchmark artifacts before the final Vault run.

CLEAN THE TREE BEFORE THE FINAL BENCHMARK AND SWAG VAULT INTEGRATION

After validation steps 1 through 7 and before steps 8 and 9, classify and remove temporary material created
before or during the campaign. Inspect `git status --short --ignored`, the preview from `git clean -ndX`,
snapshot actuals, crash files, scratch worktrees/files, and every `.output` directory under test sources.
Preserve `bin/unittests/.output` and `bin/unittests/workspace/.output`: they are canonical roots
owned by the test tooling. Remove another nested `.output` only after proving it is misplaced
generated output rather than an intentional fixture.

Remove only exact, reviewed targets. Do not use a broad destructive command against the repository,
the workspace root, or a computed path that has not been resolved and checked. Recheck for files
whose only difference is line endings, restore that noise in one batch, and retain every real
content change. Keep every final campaign commit directly on `master` so the repaired baseline is
immediately reachable from the branch it resets.

After the Swag Vault integration, only inspect its result, remove any temporary material it created,
and finish the report. If it exposes a defect, fix it and complete every affected non-privileged
rerun, review, cleanup, and commit before retrying Swag Vault, again as the final validation step.

THE CAMPAIGN MAY END ONLY WHEN

  - Every required validation result is valid for the final code and artifacts, with the affected
    focused and aggregate checks rerun after changes. Pure prose edits do not invalidate unrelated
    green code campaigns.
  - Formatting and documentation generation are idempotent.
  - The final cold-start benchmark is accepted and its history and report are current.
  - The backlog and inline-marker audit has no unresolved inconsistency.
  - No concrete defect discovered during the campaign remains open or has merely been relabeled.
  - No unexpected temporary or generated material remains.
  - All intended changes are committed on `master` and the final working tree is clean.

The campaign does not end because the first full run was mostly green, because a problem predates
the campaign, because it lives in an inconvenient subsystem, because fixing it expands the diff,
or because the session has run for a long time. If a true external blocker remains, the result is
an incomplete health reset with a precise blocker, never an all-green baseline.

REPORT

Keep a live table with each command, configuration, start/end time, result, failure root cause, fix,
and successful rerun. At the end, report the final commit(s), every validation command and result,
backlog entries removed/moved/updated, documentation regenerated, formatting performed, cold-start
benchmark campaign and acceptance result, temporary
targets removed, and any external blocker. The final statement "ready for new work" is allowed only
when every end condition above is true.
```

---

## 2. Generated-code performance

```
Read and follow the shared working protocol for prompts 2 through 7 in backlog/repo.prompts.md.

You are running a long campaign to improve the runtime performance of code generated by swc.
Read AGENTS.md and its skills, backlog/compiler.core.md, backlog/compiler.optimization.md,
and bench/README.md first.

For this campaign, the diagnosis and performance acceptance rules below take precedence over
shared instructions to edit before building or integrate the first correctness-validated batch
promptly. Keep experimental commits in the campaign worktree until they pass this performance
gate. Focused correctness repairs still follow the shared repair and validation rules; identify
them separately and never present a required repair as an established speedup.

GOAL

Make ordinary Swag programs run faster through general improvements to generated code. Compare
each bench task with its fastest non-Swag runtime from the same accepted campaign. Static code
analysis explains and selects hypotheses; runtime evidence decides whether an optimization works.
Fewer Micro instructions, fewer memory operands, or resemblance to a winner do not prove a speedup.

The campaign's runtime milestones, across every current task, are:

  - No task slower than 1.25x its fastest non-Swag runtime.
  - Geometric mean of those per-task ratios at or below 1.15x.
  - No reproducible regression in another affected task concealed by an aggregate improvement.

An accepted full campaign, 20261001-165313, recorded these native release times (ms):

  task         swag    fastest other runtime     other ms   ratio
  binarytrees  35.727  JavaScript / Node.js        10.290    3.472x
  chacha       20.627  Odin                        23.392    0.882x
  csvagg       16.168  C++ / clang-cl              15.827    1.022x
  dijkstra     28.704  C++ / MSVC                  31.598    0.908x
  fannkuch     14.882  Rust                        15.143    0.983x
  leven        12.013  Odin                        12.477    0.963x
  lz77         22.316  C++ / clang-cl              21.031    1.061x
  nbody        22.382  Zig                         16.855    1.328x
  raytrace      8.771  C++ / MSVC                   9.777    0.897x
  sha256       32.236  Zig                         36.390    0.886x
  sort         18.024  C++ / MSVC                  17.351    1.039x
  wordfreq     44.648  D / LDC                     46.687    0.956x
  geometric mean across all twelve tasks                   1.096x

This is a selection aid, not an A/B baseline or evidence for any individual edit. Recompute the
inventory and winners from the latest accepted results when starting. Exclude every Swag native
and JIT variant from the competing runtimes. Verify actual toolchain versions and build options;
do not assume C++ or LLVM wins. Treat close rankings within measurement uncertainty as ties.

The historical aggregate in bench/history.py deliberately covers the original seven tasks.
Report the complete current task set separately, including nbody, fannkuch, binarytrees, lz77,
and sort. Keep a fixed task set within each before/after comparison; never splice different
panels into one improvement claim or change the published history to hide its continuity rule.

START WITH A FOCUSED DIAGNOSIS

Use existing evidence to choose one important gap or a suspected regression. Preserve a known
baseline compiler and its inputs before editing; build that baseline if no suitable binary
exists. Do not start with a full repository campaign or a complete cross-language benchmark.
The first useful outcome is a specific, testable explanation of runtime cost, not a code change
made to meet a deadline. A short profile or focused measurement before editing is expected when
it is needed to establish that explanation.

Locate the cost inside the benchmark's timed region using sampling, hardware counters when
available, or a controlled experiment. Distinguish parsing, arithmetic, calls, allocation,
branching, memory traffic and instruction delivery. Estimate the share of time the proposed
change can affect. A visible assembly difference outside the dominant path has limited value.
If profiling facilities are unavailable, state the uncertainty and design a focused experiment
that can falsify the hypothesis; do not invent a bottleneck from instruction counts alone.

Read the competing source and its actual assembly or JIT output under the benchmark's options.
Check equivalent work, including allocation, reclamation, safety and floating-point contracts.
If the winner is not inspectable, study its execution strategy and use the fastest inspectable
native implementation as secondary code evidence. Keep the actual winner as the runtime target.
An allocator or runtime difference needs investigation at that boundary; it is not automatically
a missing Micro peephole. Follow proven causes into lowering, alias analysis, inlining, register
allocation, encoding, layout or runtime code as needed.

THE LOOP

  1. State one causal hypothesis: which measured cost dominates, which general mechanism should
     reduce it, which region should change, and what observation would disprove the idea. Select
     the target and a small set of regression sentinels before editing. Include an unrelated
     input with the same structure and a counterexample where the rule must not apply.

  2. Inspect our optimized Micro code and the final emitted machine code for that region beside
     the competitor. Inspect executed paths, spills, dependencies, calls, vector width, encoded
     sizes, loop addresses and alignment. Identical Micro code can run differently after layout:
     the csvagg regression fixed by 7e72000a8 came from loop placement, with essentially unchanged
     hot-loop instructions. Count instructions per path or iteration, accounting for nested loops
     and execution frequency; a function total is not a runtime cost model.
     Use a scratch copy with PrintMicro when needed and strip ANSI colour. Micro instruction
     references restart at each function, and a jump target is the last number on its line;
     the operand width is not a target. Confirm the executed native/JIT and inlined/out-of-line
     shape rather than assuming a standalone dump is the code the benchmark executes.

  3. Implement one coherent mechanism. Use general eligibility based on data flow, aliasing,
     ranges, loop structure and estimated benefit. Plan interacting producer, consumer and
     register lifetimes together when vectorization or scheduling requires it. The smallest
     useful transformation may span several passes; do not accumulate unrelated peepholes to
     increase the number of retained edits. State the expected follow-up for an enabling change.

  4. Complete the batch, rebuild only the needed compiler executable and inspect the final
     code again. Use static evidence to reject failed implementations quickly and to explain
     tradeoffs. Then run the focused correctness tests and benchmark checksums before timing.
     Include native, JIT and script coverage when the changed path can reach them, following
     validate-swag-changes. A checksum mismatch invalidates a performance result.

  5. Run the controlled A/B below on the target and selected sentinels before accepting the
     batch for integration. Measure a coherent group when its enabling changes are inseparable;
     compare the entire group with the preserved baseline. Do not require a complete benchmark
     campaign after every edit. A small focused experiment is the normal decision boundary.

  6. Classify the outcome using the predeclared criteria:
       - Established gain: correct output, repeatable improvement beyond control variation,
         and no detected regression in the selected sentinels at the declared precision. Keep
         the batch and record both the measured effect and the mechanism that explains it.
       - Regression: a repeatable slowdown, even with fewer instructions. Investigate, revise
         or revert; an attractive static diff cannot overrule valid runtime evidence. Separate
         mixed batches to identify the cause. An average gain does not cancel a task regression.
       - Inconclusive: the change is below resolution, controls drift, or repeats disagree.
         Record "benefit not established". Keep it pending in the worktree, combine it only with
         its stated enabling follow-up, or revert it. Do not merge it as a proven optimization.
     A code-size-only benefit is a separate result, not a runtime win under this prompt.

  7. Integrate accepted batches under the shared protocol. If incorporating concurrent changes
     affects code generation, inputs or layout, repeat the relevant A/B against that same
     combined revision without the candidate; an old timing result cannot validate a new
     combination. Keep baseline and candidate identities explicit. After integration, advance
     the baseline to the accepted revision for the next independent experiment.

  8. Run a full cross-language campaign at milestones after several accepted batches, after a
     change whose reach requires it, and before claiming the runtime milestones or completion.
     Use tools/bench.swgs and the documented admission and worker bounds. Inspect every task,
     recalculate its winner, and separate these competitive ratios from causal A/B results.
     A full campaign is a broader regression check, not a substitute for attributing a batch.

CONTROLLED A/B

Build and preserve both versions before timing. Apart from the candidate change, use identical
benchmark sources, imports, runtime sources, input data, build configuration, target features,
module names and worker counts. Isolate their outputs and affected caches. Record revisions,
compiler and executable hashes, exact commands and the timed-region definition. For a runtime
change, the corresponding runtime difference is part of the candidate and must be named.
Temporary binaries, dumps, probes and logs stay outside every checkout.

Measure the generated program's intended kernel with the same boundaries as the benchmark.
Keep compilation, input generation, warmup and setup outside the region when the benchmark does.
Whole-process CPU time may corroborate a result but cannot replace the kernel measurement when
it includes substantial untimed work. Use the benchmark harness's process isolation and performance
core affinity. A custom probe must preserve those controls and avoid changing the published task.

Before collecting samples, state the question, minimum useful gain, non-regression tolerance,
control-stability checks, sample budget and stop rule. Choose attainable precision from an
unchanged-binary A/A control, not from the candidate's result. Do not widen a tolerance to admit a
regression, relax a failed gate, cherry-pick repetitions or keep sampling until one run wins.

Warm both versions, interleave pairs and balance A/B versus B/A order. Include an unchanged
control across the measurement window, retain every sample, and report paired ratios with their
spread or uncertainty rather than comparing independent minima. Confirm a claimed gain in a
second independent window. Select sentinels by the affected mechanism; use csvagg for changes to
layout, calls or register pressure, and nbody for floating-point, inlining or vectorization changes.
Expand coverage when evidence shows that the initial sentinels do not bound the effect.

Build admission is not measurement isolation. Do not launch builds or tests alongside the timed
runs. A failed control makes the experiment inconclusive; continue independent source analysis
while waiting for a suitable window. Never stop another user's or agent's work to make room.
Partial A/B experiments retain their own evidence and never enter the full campaign history.

RULES AND STOPPING

  - Never change a benchmark's computation, workload, timed boundaries or checksum to obtain a
    speedup. Scratch variants may diagnose a mechanism but cannot replace the original task's
    acceptance measurement. Preserve language semantics, including aliasing and FP policy.
  - Never recognize benchmark names, exact constants or thresholds selected to fit one example.
    Explain how the optimization benefits ordinary code with the same proven properties.
  - Execution performance is the primary objective. Report compile time, memory and code-size
    costs at milestones or when the change makes them material; do not call extra analysis
    worthwhile solely because the emitted code looks simpler. Improve an expensive analysis
    without discarding an established runtime benefit merely for compile-speed convenience.
  - Keep rejected or unresolved hypotheses with their code and measurement evidence in the
    existing matching backlog entry. Search before allocating a new identifier, state a concrete
    next action, and avoid repeating experiments already ruled out under the same conditions.
  - Between some batches, audit a relevant pass's generality and its interaction with allocation
    or layout. Keep the audit focused; any resulting optimization passes the same acceptance gate.

The campaign reaches its target when accepted measurements cover every current task, meet both
runtime milestones, and establish no outstanding reproducible regression, with correctness checks
valid for the final revision. Continue beyond a milestone when profiling identifies a concrete,
material remaining opportunity and the requested campaign budget permits it.

If three evidence-based rounds across the current task set produce no established gain and leave
no credible actionable hypothesis, report a plateau and the remaining gaps. Do not describe that
as reaching the target. Unavailable stable measurements are a blocker to a performance claim,
not proof of success or exhaustion. A requested time limit ends the run with pending experiments
and unestablished benefits identified explicitly.

REPORT

After each round, give one compact table: task and competing runtime/toolchain, observed
bottleneck, hypothesis, relevant before/after machine-code evidence, paired runtime effect and
uncertainty, unchanged-control and sentinel results, correctness checks, decision and commit.
Distinguish experimental, accepted and integrated changes. Report rejected and inconclusive
results as well as wins. At a full milestone, give all current per-task competitive ratios and
their geometric mean, naming the exact campaign and task set; label the seven-task historical
aggregate separately. Never substitute instruction savings or a checksum pass for a speedup.
```

---

## 3. Safety without annotations

```
Read and follow the shared working protocol for prompts 2–7 in backlog/repo.prompts.md.

You are running a long campaign on Swag's safety guarantees. Read AGENTS.md and the skills it
points to first, then backlog/compiler.safety.md, backlog/compiler.core.md, and the language
reference page bin/reference/modules/language/src/013_004_borrowing.swg, which states what the
language currently guarantees.

Know the test-resolution trap: a scratch module
compiled with swc test -d <dir> resolves swag@std OUTSIDE the worktree, so it silently measures the
main checkout's standard library rather than yours. Any probe of behavior that crosses a module
boundary has to live in bin/unittests inside the worktree.

Use the latest accepted green campaign as the starting correctness reference. Begin with the
smallest positive and negative tests for the first selected rule; do not run a full baseline suite
before editing.

GOAL

Bring Swag to Rust-class memory safety WITHOUT asking the user to annotate anything. No lifetime
parameters, no borrow syntax, no ownership sigils beyond what already exists. The compiler infers
what it needs from the code as written, or it says nothing. That constraint is the whole point of
the campaign: the value is a guarantee that costs the reader no syntax.

The classes that must be caught at compile time, with no annotation:

  - Use after free, use after move.
  - A view (string, slice, pointer into a container) read after the storage it views was moved,
    reallocated, or dropped.
  - A container mutated while a view into it is live - iterator invalidation.
  - A borrow escaping the scope that owns it, including through a return value, an out parameter,
    a container store, or a captured closure.

Where it stands: all four classes are caught, and the line is drawn. The borrow rules live in
src/Compiler/Sema/Helpers/SemaEscape.cpp, are always on, and consult no attribute and no build
configuration - they are the language, and the reference says so. What stays under
#[Swag.Sanity] is the other half: the backend analyses that PROVE a runtime fault (division by
zero, overflow, null dereference, constant out-of-bounds, undefined read, use after free, use
after move) in src/Backend/Sanitizer/Checks. Tests live in bin/unittests/sanity - borrow_escape,
borrow_invalidation, collection_mutation - and bin/unittests/safety.

What is left is precision, and the live entries in `backlog/compiler.safety.md` are the authority.
They currently include parameter-owned views, macro and inline expansions judged against the
wrong body, and a backend check the language rule has made unreachable from source. Re-read that
file before choosing a round;
do not preserve this summary after an entry moves or is retired.

THE LOOP

For each coherent batch of related checks, in this order, and do not skip step 1:

  1. Write the tests first, both halves. The positives that MUST fire, in bin/unittests/sanity,
     and - this is the half that decides whether the check is usable - the negatives that must
     stay SILENT: an interface or pointer to the value itself, a method that only reads or assigns
     fields, a view rebound after the container grew, a container of views whose owner outlives
     them. A check with no negative tests is a check that will be turned off.
  2. Implement the smallest analysis for the batch. Inspect related edits together, then build
     once and run the focused positive and negative tests. Rebuild sooner only when the next edit
     depends on the compiler's actual verdict.
  3. Exercise one affected consumer early when the rule crosses a module boundary. At a milestone
     after several retained batches, after a rule with unusually broad reach, and before claiming
     the rule works across the repository, sweep the whole tree for false positives: swc
     tools/build.swgs, swc tools/std.swgs, swc tools/apps.swgs, swc tools/examples.swgs, and swc
     tools/reference.swgs. Include test bodies: a build-only sweep misses them, including the
     standard-library cases that have exposed false positives. A clean sweep becomes evidence only
     after the check is proved to fire.
  4. Triage every hit, one at a time, into exactly one of two buckets: a real defect in bin/ (fix
     it, it is a genuine find) or a false positive (fix the analysis). There is no third bucket.
  5. Never silence a false positive by narrowing the check until it stops firing. That is how a
     check ends up complete and useless, firing on nothing. If a shape genuinely cannot be judged,
     say so as a finding and leave the check firing on what it can prove.
  6. Before claiming a new always-on guarantee across the tree, run the relevant DevMode,
     configuration, and Release sequences and confirm both firing cases and clean consumers.

DO NOT STOP AT THE FIRST FAILURE

A new check that lights up forty call sites across bin/ has not failed - it has just started. Work
the list down. Expect several rounds where the analysis gets weaker before it gets stronger, and
expect at least one shape that needs a piece of information sema does not currently keep. When
that happens, the answer is usually to extend the summary that already crosses module boundaries
(#[Swag.BorrowSummary]), not to give up on the shape.

A campaign milestone ends when the retained classes are caught, the whole tree is clean, and what
the language guarantees is written down in the reference. An individual batch needs focused
evidence and can be integrated before that milestone. The campaign does not end because a check was
noisy, because one shape needed information that was not there, or because a sweep came back with
hits.

RULES

  - Zero annotations. If a check can only be made sound by asking the user to write something, it
    is out of scope - say so and record why.
  - False positives are the only thing that can kill this. Weigh every design choice by what it
    would reject that is correct.
  - Probes that test a summary crossing a module boundary must live in bin/unittests. A scratch
    module compiled with swc test -d <dir> resolves swag@std OUTSIDE your worktree and silently
    measures the main checkout's standard library.
  - A clean sweep is only evidence once you have proved the check fires. Plant a deliberate fault
    in a module that imports std, watch it be reported, then remove it - a check that silently
    reaches nothing looks exactly like a clean tree.
  - A language rule must reach the same verdict in every build configuration, so never branch it on
    something the configuration also drives. Testing '#[Inline]' is the trap: it reads like a
    property of the callee and behaves like a property of the build, and it made a view visible in
    devmode and invisible in release. Ask what actually happened - an expanded call no longer
    resolves to a CallExpr - instead of asking what was requested. '--all-cfg' is what catches
    this, and it catches nothing if you only ever run the default configuration.
  - Compile time is a constraint: a whole-program analysis that doubles sema is not acceptable.
    Measure it.
  - Every defect the analysis finds in bin/ gets fixed in the same campaign. That is the proof the
    check is worth having.

REPORT

Per round: the check, the tests added, the sweep result, every hit and which bucket it went in. At
the end: what the language now guarantees, always-on, with no annotation - written as prose a user
could read.
```

---

## 4. Compilation speed

```
Read and follow the shared working protocol for prompts 2–7 in backlog/repo.prompts.md.

This is a code-iteration campaign for statically proven compiler savings. Its measurement rule
overrides the shared protocol's optional measurement milestones for planned speed work: do not run
an initial baseline, `bench/compile.py`, A/B timings, a profiler, or a four-workload check, including
at milestones or before integration. The dedicated benchmark campaign owns elapsed-time, CPU and
peak-memory measurements. If a change needs timing to establish that it saves work, discard it and
try a change whose saving can be proved from the code.

You are running a compiler-speed campaign on swc. Read AGENTS.md and the skills it points to first,
then compiler.core.004 and compiler.core.030 in backlog/compiler.core.md and
compiler.optimization.029, compiler.optimization.039 and compiler.optimization.045 in
backlog/compiler.optimization.md. Use their existing profiles to choose a costly internal path and
their rejected experiments to avoid repeating work. Start editing compiler code after this review.

RELEASE COMPILER ONLY

Build and validate planned speed work only with the Release compiler, `bin/swc.exe`.
Use an existing recent green Release campaign as the correctness reference.

GOAL

Make the compiler implementation itself faster. The result must perform the same compilation work
in less wall time and process CPU: faster lexing and parsing, faster semantic analysis, less
contention, fewer locks, better scaling with the compiler worker count, cheaper lowering and JIT
preparation, faster backend optimization, register allocation and encoding, fewer redundant walks
and lookups, or cheaper allocation and data structures on those paths.

This campaign is not an incremental-build, cache, manifest, artifact-reuse, relink, module-format,
documentation or formatting campaign. Do not claim a win by skipping compiler work, reusing a
previous invocation's result, changing invalidation, avoiding linking, or moving time outside the
measured command. The same source inputs must go through the same required compiler phases and
produce equivalent output. A cache or pipeline change belongs to another campaign even if it
improves one of the edit-loop numbers below.

Targets, all on this machine. The readings below are from 2026-09-23 with Release 0.1.1056 and
six workers; they are context for the dedicated benchmark campaign:

  - std/core rebuild (360 files): 2.63 s. Target under 1.0 s.
  - Warm no-op build of the same: 50 ms. Guardrail under 100 ms; not an optimization target here.
  - Edit one file in core, rebuild: 2.41 s. Use it to expose repeated compiler work, but do not
    solve it with cache or invalidation changes in this campaign.
  - Hello world, source to linked executable: 211 ms. Target under 50 ms.

The hello-world reading is far above the 89 ms this prompt used to quote because runtime grew; see
compiler.core.030. Do not repeatedly remeasure all four workloads between code hypotheses.

For context on where the bar already is, from campaign 20260806-174758: swc builds the bench tasks
in 93-132 ms against clang-cl's 481-647 ms and rustc's 425-585 ms. This campaign is not about
beating them. It is about the loop a person actually sits in.

STRUCTURAL EVIDENCE

Use existing profiles to choose a path, then establish each saving from code: fewer traversals,
calls, allocations, lookups, or synchronization steps for equivalent inputs and output. Do not add
profiling-only branches to the compiler. Leave uncertain timing, scaling, CPU, and peak-memory
tradeoffs to the dedicated benchmark campaign. Keep its durable `history.json` untouched here.

THE LOOP — PRIORITIZE CODE ITERATIONS

  1. Use a recent profile to select one costly internal stage. Give one concrete hypothesis and a
     predicted effect; spend minutes, not hours, on investigation before the first edit.
  2. Group related edits into a coherent code batch. Inspect the final diff for equivalent output
     and a clear reduction in compiler work, then rebuild Release once for the batch. Rebuild
     earlier only when compiler output determines the next edit. Discard an uncertain tradeoff
     rather than timing it in this campaign.
  3. Retain a structurally proven saving after its focused correctness check. Record the operation
     removed without assigning a percentage or claiming a measured speedup. At a milestone,
     review accumulated changes for hidden CPU, memory, and generated-code tradeoffs; send any
     change that needs measurement to its owning campaign.
  4. Before retaining a speed batch, use a focused Release-compiler check that exercises it.
     Broader Release checks follow the shared milestone and risk rules.
  5. Keep failed experiments out of retained batches; summarize their reason briefly so the same
     dead end is not retried.

Aim for several distinct code hypotheses per work session. If most elapsed time is going to tests,
report writing or log collection, stop the optional work and return to code.

OPTIMIZE THE COMPILER, IN THIS ORDER OF EVIDENCE

Choose the next item from existing profiles and structural evidence, not from this list's order:

  1. Lexer and parser: byte/token scanning, source traversal, token storage, hashing, allocation,
     repeated decoding and syntax-tree construction.
  2. Semantic analysis: symbol and type lookup, overload/generic work, substitute chains, repeated
     AST walks, compile-time dependency discovery and JIT preparation.
  3. Scheduling and synchronization: job granularity, queues, wakeups, barriers, mutex/RW-lock
     contention, false sharing and serial critical paths. Preserve deterministic compiler behavior;
     leave changes whose benefit requires scaling measurements to the benchmark campaign.
  4. Lowering and backend: `CodeGenJob`, Micro construction, SSA construction, pass-manager
     convergence, repeated analyses, optimizer data structures, register allocation, instruction
     selection, encoding and object construction.
  5. Allocation and locality inside those phases: reuse capacity, shrink hot records, release
     phase-local storage and replace pointer-heavy structures when existing evidence attributes
     the cost. Defer uncertain memory/CPU trades to the benchmark campaign.

Optimize algorithms and implementation, not generated program quality. If a backend change alters
emitted code, prove the code is equivalent and use static generated-code inspection; defer any
uncertain quality tradeoff to campaign 2.

DO NOT STOP AT THE FIRST FAILURE

Compiler hot paths are mature, so many valid improvements will land below the noise floor. Retain
a correctness-certified change when its mechanical proof shows less compiler work. Accumulate
these small savings and leave aggregate timing to the benchmark campaign. Label an unmeasured
saving as structural, without a percentage claim. Revert speculative rewrites and unjustified
complexity quickly, then try the next idea.

The campaign can claim its structural work complete when no concrete statically provable compiler
saving remains. The speed targets and guardrail workloads are judged by the dedicated benchmark
campaign; report them as unverified here. One difficult optimization avenue does not end this one.

RULES

  - Never trade correctness for speed.
  - Preserve generated-code quality by static inspection; leave uncertain tradeoffs to campaign 2.
  - Preserve memory behavior where code inspection can prove it; leave uncertain tradeoffs to the
    dedicated benchmark campaign.
  - Do not make quantitative speed or memory claims from structural evidence alone.

REPORT

After each retained batch, give the changed code and its structural effect in a short summary. At
a milestone, report retained batches and tests; quote historical targets only as context. Report
rejected ideas in a sentence each. Do not commit raw logs or long chronological notes.
```

---

## 5. Compiler memory

```
Read and follow the shared working protocol for prompts 2–7 in backlog/repo.prompts.md.

You are running a memory campaign on swc. Read AGENTS.md and the skills it points to first, then
backlog/compiler.core.md compiler.core.005.

Use the last accepted memory and compile-time measurements as context. Start with the highest
attributed memory cost and edit before launching a full test or benchmark campaign. When a retained
batch needs a quantitative comparison, measure its affected workload against a fresh baseline in
the same session, recording peak working set and wall time together.

GOAL

Make swc need a fraction of what it needs today, at the same speed. Memory is what bounds how many
modules can compile at once, and it is what makes the difference between a language you can run as
a script and one you cannot.

Where it stands (2026-09-05, Release swc.exe, --num-cores 6, after the first round: finished
jobs release their Sema and CodeGen, 64 KiB arena blocks, api-export index dropped):

  - std/core rebuild (50 690 lines): 517 MB peak working set in devmode, 360 MB in release.
    Before the round: 731 MB and 638 MB. That is still roughly 10 KB of resident memory per
    source line in devmode.
  - Hello world: 60 MB peak (was 73 MB). To print one line.
  - Building the bench tasks: swc peaks at 58-66 MB (was 74-83 MB) where clang-cl peaks at
    69 MB and MSVC at 82-101 MB. rustc peaks at 201 MB.
  - The largest block still resident at peak is the static sanitizer's flow state; see
    compiler.core.005 for the attribution and the next lever.

Targets:

  - core rebuild under 250 MB devmode.
  - Hello world under 50 MB.
  - Bench task builds at or below clang-cl's 69 MB.
  - Compile time unchanged, measured, not assumed.

MAKE THE NUMBER ATTRIBUTABLE WHEN CHOOSING A LEVER

There is no per-subsystem memory accounting today - only an OS peak. The split between AST, types,
symbols, constants and Micro is currently UNKNOWN. Use existing traces first. Capture the split
with an external heap profiler against one affected workload only when existing evidence cannot
identify the next lever; do not add per-allocation tracking or optional profiling branches to the
compiler.

TWO SUSPECTS WORTH CHECKING EARLY

Both are already written down and neither is confirmed:

  - Nothing is released between stages. Post-codegen, the whole AST and every Micro function are
    probably still resident for the entire module.
  - Per-function Micro state is retained for the whole module rather than freed as each function
    finishes.

Inspect the relevant ownership and lifetime code before changing either. Use focused accounting
when source inspection cannot establish which one matters.

THE LOOP

  1. Choose an attributable block from existing evidence; use one focused profile only if needed
     to distinguish candidate blocks. Name why it remains alive at peak.
  2. Group related lifetime or representation edits into one coherent batch. Free the block
     earlier, store it smaller, or do not build it at all - in that order of preference.
     "Do not build it" is usually the real answer and usually the one that gets skipped.
  3. Build once when the batch is ready, then run its smallest focused correctness check. Fix any
     failure before retaining it; do not run the full compiler sequence for each small edit.
  4. Measure peak AND wall time on the affected workload when the batch's benefit or speed cost
     cannot be established from source. Compare with a baseline from the same measurement session.
     A memory win that costs speed is not a win here.
  5. At a measurement milestone, compare DevMode, Release, and the affected workloads as needed
     for a quantitative campaign claim; record peak memory and wall time together.

DO NOT STOP AT THE FIRST FAILURE

Freeing something early will crash the compiler the first time, because something downstream still
reads it. That is the expected outcome, not a reason to abandon the lever: it identifies the real
lifetime of the data, which is the information you were after. Find the reader, decide whether it
should be reading that at that point, and either move the free or restructure the reader.

Expect to be wrong about which subsystem dominates. The accounting exists precisely because
everyone's intuition here has been wrong before.

The campaign ends when the four targets are met with compile time unchanged. It does not end
because one attempt to free the AST early crashed, or because one subsystem turned out to be
smaller than expected.

RULES

  - Peak working set is the number, not allocations or bytes requested.
  - Compile time is a hard constraint. Measure it alongside memory when judging a retained memory
    gain, using order-alternated medians for quantitative claims rather than timing every edit.
  - The runtime allocator's arenas are never returned to the OS by design. Understand that before
    reading any peak: a fix that only reduces allocation churn may not move the peak at all.
  - Coordinate with campaign 4 on the parallel module scheduler: it multiplies peak memory by the
    number of concurrent modules. Its structural changes may run concurrently with this campaign;
    evaluate the combined revision at the next measurement milestone.

REPORT

Peak memory per workload as a table, current versus target, next to wall time for the same
workload - always both, so a trade is visible the moment it happens.
```

---

## 6. Compiler code health

```
Read and follow the shared working protocol for prompts 2–7 in backlog/repo.prompts.md.

You are running a mechanical code-health campaign on the swc compiler itself. Read AGENTS.md and
the skills it points to first, especially modify-swag-codebase,
modify-swag-codebase/references/cpp-coding-rules.md, and validate-swag-changes. This is an
implementation campaign, not an audit, but its safety boundary is absolute: make only changes whose
semantic equivalence can be established directly from the source. If a proposed improvement needs
design judgment, changes a contract, or carries any plausible regression risk, leave it unchanged
and report it as an unattempted design idea. A concrete defect discovered while inspecting or
validating the source still follows the shared repair rule.

SCOPE

Restrict edits to project-owned compiler and support code under src/ and the project files needed
to describe it. Exclude vendored code, generated output, language behavior, public module APIs,
diagnostic wording, command-line behavior, serialized formats, ABI, runtime contracts, cache
formats, and build-system semantics.

Remove references from compiler implementation code to specific content under bin/, including
examples, tests, reference pages, applications, and standard modules. The compiler must not know
which sample happens to exercise it. Keep bin/ paths in test fixtures, repository tools, and
documentation that actually operate on those workspaces; replace compiler-side special cases with
the existing general contract only when source inspection proves equivalent behavior. If a path
is part of a user-visible default or another contract, leave that mechanical cleanup untouched;
repair an actual broken contract under the shared defect rule.

Remove references to the x64 encoder from compiler code outside the backend areas that own x64
instruction selection, encoding, and their direct integration. Keep target-specific details at
those boundaries; use an existing target-neutral interface when that is mechanically equivalent.
Do not disguise x64 work behind a new generic name or change the supported target contract.

Campaign 4 owns changes intended to reduce compile time, CPU work, contention, or memory traffic
on compilation paths, with measurements and performance guardrails. This campaign owns source
quality and dependency boundaries, with a source-based equivalence argument. Do not claim a prompt
6 gain from faster compilation, and do not move a performance hypothesis into this campaign to
avoid measuring it. If a cleanup exposes a separate speed opportunity, leave that opportunity for
campaign 4.

The campaign covers these mechanical improvements:

  - Include health: remove unused and duplicate includes; replace accidental transitive includes
    with direct includes at the real use site; move implementation-only dependencies from headers
    to source files; use forward declarations where a complete type is not required; split stable
    enums, keys, lightweight value types, and persistent data contracts from heavy service headers;
    break unnecessary include cycles; and keep every public header self-sufficient.
  - Dependency fanout: identify broadly consumed headers that aggregate unrelated facilities and
    separate them into cohesive leaf contracts. Use dependency counts or the existing build
    dependency graph as structural evidence, not elapsed-time or memory benchmarks. Do not add a
    pointer, allocation, virtual dispatch, PIMPL, type erasure, or runtime indirection merely to
    reduce include fanout. Fanout is the weakest goal here: when cutting it would force a
    duplicate to survive, delete the duplicate and accept the wider include.
  - Code reduction: the campaign's first priority, ahead of fanout and ahead of diff size. Remove
    exact duplication, near-identical copies that differ only in spelling, a local binding, an
    assertion or a diagnostic id, redundant wrappers, repeated declarations, unreachable
    duplication after an unconditional exit, and equivalent boilerplate. A file-local helper
    written a second time in another file is already the defect: collapse the whole family the
    moment a twin turns up, and never leave a copy standing because one of its users would then
    have to include more, qualify a call, or gain a header. Finding the shared version a home is
    part of the work, not a reason to stop — put it on the type it interrogates, in the domain
    namespace that owns the area, or in a new cohesive leaf header, whichever reads best. When the
    copies are not textually identical, unify them on the strictest behavior any copy has: an
    assertion present in one and absent from another is kept. That is a deliberate behavioral
    change, so validate it and say so in the report; if the assertion then fires, it has found a
    real defect and you fix it in a separate focused repair batch.
  - Simplification: simplify control flow, expressions, local initialization, and helper structure
    only when evaluation order, conversions, overflow behavior, lifetime, ownership, allocation,
    synchronization, and generated code remain unchanged.
  - Naming: perform complete, mechanical renames of private or internal identifiers when the new
    name is materially clearer. Do not rename exported symbols, externally visible strings, files
    consumed by tools, reflection targets, configuration keys, or compatibility surfaces.
  - Comments: remove stale, duplicated, or narrating comments; correct comments that no longer
    match the code; and add concise English comments for non-obvious invariants, ownership,
    lifetimes, concurrency assumptions, binary layout, or intentionally unusual low-level code.
    Never use comments to excuse unclear code that can be made clear mechanically.
  - Local consistency: align nearby code with established repository idioms, reuse an existing
    equivalent helper, remove obsolete suppressions whose cause no longer exists, and keep project
    file entries and filters accurate after header splits or renames.

HARD SAFETY BOUNDARY

Preserve observable behavior exactly. In particular, do not change algorithms, public or internal
contracts, object layout, data-member order, virtual dispatch, ownership, allocation count or
arena, locking, atomics, exception behavior, error propagation, evaluation order, integer or
floating-point semantics, generated machine code intentionally selected by the implementation, or
hot-path work. A behavioral defect discovered during the campaign is handled as a separate focused
repair batch under the shared protocol, with its own regression test; it is not disguised as a
mechanical cleanup.

Introducing a shared helper, a new member on the owning type, or a new leaf header in order to
delete a duplicate is expected work, not an abstraction to be avoided; only invent one that no call
site needs. A reduction must stay as direct to read and as fast to run as the original — share
through an inline or header-side definition wherever the copies were being inlined, so the emitted
code does not move — but a longer include closure, a qualified call site, a call-site sweep, or one
more file is an acceptable price for deleting a copy.

Do not apply unreviewed bulk fix-its, blanket formatting, speculative modernizations, global
search-and-replace without symbol verification, warning suppressions, or cosmetic churn. When
equivalence is not obvious in the diff, the edit is out of scope.

DISCOVERY

Build a short source-based inventory before editing. Look for high-fanout headers, include cycles,
headers depending on service implementations for a small type, repeated code sequences, trivial
wrappers, stale comments, unclear private names, redundant branches, and project-file drift. Static
analysis and compiler warnings may supply leads, but no tool diagnostic is authority and no
tool-specific report is the campaign's completion gate.

Prioritize changes with broad maintenance value. Prefer a small, mechanically provable diff, but
never drop a duplication because collapsing it touches many call sites: a qualification sweep is
mechanical and belongs in the campaign. Group the inventory into coherent batches such as one
header family, one internal rename, or one duplication pattern. A duplication spanning two
subsystems is still collapsed, at the boundary they already share; only a genuine compatibility
decision is grounds to skip.

THE LOOP — PRIORITIZE CODE ITERATIONS

  1. Select one small source-quality issue from the inventory. Read its affected declarations,
     definitions, include paths, and callers. State the equivalence argument and the exact
     dependency, duplication, bin/ reference, or misplaced x64 dependency being removed. Spend
     minutes, not hours, investigating before the first edit.
  2. Make the smallest complete edit. Add direct includes to real users before removing a
     transitive include. Keep lightweight types by value; do not hide real layout dependencies.
     Search for all exact references and update them in the same batch.
  3. Inspect the completed batch's diff. Reject unrelated formatting, line-ending churn,
     reordered code, or an edit whose safety depends on an assumption not visible in the source.
  4. Choose the evidence for the changed surface: an incremental DevMode build for executable
     compiler changes, a project-file parse for entry changes, or a static diff check for comments.
     Use a focused test when moved or refactored behavior has a meaningful test seam. Broader
     checks follow the shared milestone and risk rules.
  5. Retain only changes whose equivalence argument remains clear after review.

Aim for several distinct code hypotheses per work session. Keep batches small and reviewable and
return to code promptly after the next decision boundary. The campaign may be broad in aggregate,
but each transformation must remain locally obvious.

EVIDENCE

Also build Release when a mechanical batch crosses compiler architecture, shared headers,
conditional compilation, or source sets. Do not run performance measurements for a purely
mechanical cleanup; if an edit needs benchmarking to establish equivalence, it is outside this
campaign's mechanical work.

Verify that every new header is present in the project and filters.

THE CAMPAIGN MAY END ONLY WHEN

  - Every retained edit belongs to one of the categories above and is demonstrably
    behavior-preserving, except where a deliberate unification onto the strictest copy is reported
    as such.
  - No family of duplicated definitions is knowingly left standing. Each one is collapsed, or
    reported with the specific contract, layout, or behavioral difference that blocks it. An
    include cost, a call-site sweep, a namespace qualification, or the need to choose a home are
    not such reasons.
  - Headers are self-sufficient, direct users own their includes, and each new leaf header has one
    cohesive purpose.
  - No incomplete rename, stale reference, obsolete project entry, new suppression, generated file,
    vendored edit, line-ending-only change, or misplaced output remains.
  - The validation selected from the final diff is green after the last source edit.
  - Mechanical batches contain only the intended code-health changes; defect repairs are separate
    focused batches.

Do not claim completion for design ideas deliberately left outside the mechanical boundary. Those
are unattempted ideas, not encountered defects. Duplication is not one
of them: a surviving copy is a failure of this campaign unless a contract, a layout, or a
behavioral difference genuinely blocks it, and the report must name which.

REPORT

Report the worktree path and branch, starting commit, coherent cleanup batches, important include
or dependency reductions, comments added or removed, internal renames, code reductions, skipped
non-mechanical findings, unchanged SWC_BUILD_NUM, files changed, and every validation command with its
result. Report structural dependency counts when useful, but no timing or memory measurements.
```

---

## 7. Swag code and API quality

```
Read and follow the shared working protocol for prompts 2–7 in backlog/repo.prompts.md.

You are running a repository-wide Swag code and API quality campaign across bin/. Read AGENTS.md,
then the skills modify-swag-codebase, validate-swag-changes, write-idiomatic-swag-code,
design-swag-bin-modules, and write-swag-public-api-docs. Read tools/README.md, backlog/README.md,
and the relevant domain backlogs. Apply the application, visual identity, theme, dialog, compiler
message, and syntax-reflection skills whenever a batch enters their scope.

GOAL

Make bin/ the reference showcase for the Swag language. A reader should be able to copy its code
and learn the best current language idioms, clear design, safe resource handling, and coherent
APIs. This is an implementation campaign: clean up, improve, refactor, simplify, and finish the
code and its public contracts. An inventory of problems alone does not satisfy the goal.

Quality is judged by correctness, clarity, consistency, useful API completeness, and the code a
caller actually writes. Shorter code is valuable when it expresses the same intent more clearly;
line count and use of the newest syntax are not goals of their own.

COVER ALL OF BIN/

Inventory the actual tree, including every project-owned .swg and .swgs source, module descriptor,
and public API. Cover runtime, every standard module, every application, examples, standalone
scripts, executable language-reference pages, compiler suites, module tests, and test helpers.
Discover additional directories from the tree instead of treating this list as exhaustive.

Keep a coverage table outside the checkout with each area, reviewed files and API
families, findings, retained changes, validation, and remaining work. Every project-owned source
must receive a semantic review; a pattern search or formatter pass alone is not review. Inspect
public declarations together with implementations, documentation, tests, and representative callers.
Inspect every member of a repeated family before marking that family complete.

Classify generated sources, vendored sources, binary assets, fixtures, and compilation artifacts
explicitly. Review project-owned generation inputs and integration code; regenerate derived output
through its owning tool. Preserve upstream code and fixtures whose unusual form is intentional.
Compiler regression inputs may deliberately use awkward syntax, redundant code, or failing code:
preserve the exact behavior they test instead of modernizing away their purpose.

WHAT TO IMPROVE

  - Idiomatic Swag: apply the current language reference and write-idiomatic-swag-code to value
    returns, inference, ownership and moves, borrowing, cleanup, error propagation, interfaces,
    iteration, collections, pattern matching, and compile-time facilities where they improve the
    code. Replace stale idioms and unnecessary low-level work with existing language or library
    facilities. Do not imitate another language or introduce clever syntax without reader value.
  - Simplification: remove dead code, redundant state, needless temporaries and wrappers, repeated
    conversions, unnecessary nesting, and duplicate implementations. Collapse real duplication at
    its owning abstraction; keep algorithms and invariants visible. Prefer a cohesive helper or
    type over copy-paste, but do not create a framework for hypothetical callers.
  - Structure: give modules, types, functions, and files a clear responsibility. Separate reusable
    library behavior from application policy, keep implementation details private, clarify names,
    reduce unnecessary dependencies, and align related implementations around one consistent design.
  - Correctness and resources: inspect bounds, empty inputs, overflow, partial failure, allocation,
    ownership, view lifetime, cleanup, cancellation, and concurrency where present. Preserve
    evaluation order and numeric semantics during cleanup. Fix discovered behavioral defects at
    their root and add regression coverage at the owning boundary.
  - API quality: review whole operation families for naming, symmetry, useful completeness, type
    consistency, parameter order, defaults, mutability, ownership, borrowing, lifetime, allocation,
    failure behavior, and module boundaries. Verify contracts through real caller code. Simplify
    awkward caller sequences, remove accidental public surface, and fill demonstrated gaps without
    speculative API growth. Make error behavior predictable and failure states well defined.
  - API changes: make a deliberate before/after contract decision, assess compatibility, and update
    every in-repository caller, test, example, reference page, and public comment in the same batch.
    Respect documented compatibility requirements and explain any migration for external callers;
    do not leave half-renamed families or compatibility wrappers with no concrete requirement.
  - Teaching quality: examples and reference code must show the recommended way to solve their
    problem. Keep them small and complete, with correct failure handling and resource cleanup.
    Public documentation must explain contracts, edge cases, and ownership, and use examples that
    compile against the final API. Replace stale or narrating comments with clear code or concise
    explanations of the reason behind a non-obvious choice.
  - Efficiency: remove demonstrably unnecessary copying, allocation, repeated work, or poor data
    structure choices. Measure changes whose performance depends on workload; preserve deliberate
    fast paths unless evidence supports the replacement. Do not trade clarity for speculative speed.

THE LOOP

  1. Pick one cohesive area or cross-module API family from the coverage table. Read its full
     implementation and callers, establish the current contract, and identify concrete weaknesses.
  2. State the intended improvement and the narrowest validation that observes it. Distinguish a
     behavior-preserving refactor from a bug fix or public contract change.
  3. Implement the complete improvement, including all affected consumers and documentation.
     Search the repository for stale names, duplicated alternatives, and obsolete usage patterns.
     Keep unrelated cleanup in separate, reviewable batches.
  4. Review the diff for correctness, idiomatic language use, ownership, API consistency, and
     teaching value. Remove cosmetic churn, accidental generated changes, and line-ending noise.
  5. Run the validation selected by validate-swag-changes: the owning module's focused tests,
     compiler regression boundary, affected consumer, example/script smoke, or reference page.
     Add configurations, compiler builds, and broader coverage only when the changed behavior
     requires them. Inspect affected goldens; never promote a difference merely to make tests pass.
  6. Update coverage and continue through every remaining area. A green build, one cleaned module,
     or a large diff does not mean the whole tree has been reviewed.

IMPROVE THE PLATFORM WHEN IT GETS IN THE WAY

When idiomatic Swag is awkward because of a library defect, compiler defect, or missing language
capability, investigate the cause. Fix discovered defects with focused regression coverage under
the shared protocol; do not spread local workarounds across bin/. Surface syntax changes require
reference and editor updates. If a missing capability requires a design decision, keep that
separate from a concrete defect and do not claim the affected area is complete until the decision
and implementation are resolved.

THE CAMPAIGN MAY END ONLY WHEN

  - Every project-owned Swag source and public API family under bin/ has been reviewed, with
    explicit coverage and justified exclusions for generated or upstream material.
  - Every actionable improvement found in scope is implemented and validated; every remaining
    design or external blocker is identified precisely and prevents a claim of full completion.
  - APIs, implementations, callers, tests, examples, and documentation agree, with no stale names,
    partial migration, unexplained duplicate implementation, or obsolete recommended idiom.
  - Validation selected from the complete final diff is green, including affected consumers and
    inspected golden outputs. No disabled test, weakened assertion, or unreviewed golden hides a
    regression. Earlier evidence is rerun when a later change invalidates it.
  - Formatting is consistent, required generated documentation is current, and no temporary output,
    accidental upstream edit, or line-ending-only change remains in the final diff.

Do not stop after the easy style fixes or the first directory. Continue until the coverage table
accounts for the whole tree. If completion is blocked, deliver the validated improvements and
state exactly what remains; never claim that bin/ is perfect on the strength of a sample.

REPORT

Report the worktree and branch, reviewed areas and exclusions, meaningful before/after examples,
refactorings and simplifications, API contract changes and caller migrations, defects fixed,
platform findings, documentation updates, and every validation command and result. Include the
final coverage table and any remaining blockers so the whole-tree review can be verified.
```
