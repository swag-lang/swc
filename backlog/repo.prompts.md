# Campaign Prompts

Seven long-running campaigns, one prompt each, ready to copy into a fresh session. They are not
tasks: each one is a target that takes many rounds to reach, and each prompt is written to keep an
agent working through the rounds instead of stopping at the first thing that does not work.

Each prompt is self-contained. It names the goal, the evidence to collect, the loop to run,
the rules that must not be broken, and — most importantly — the condition under which the campaign
is allowed to end. Every number quoted below was measured on this tree and is reproducible with the
command next to it. Re-measure historical numbers when the campaign needs them; use a fresh
source inventory for code-quality campaigns.

| Campaign | Target |
| --- | --- |
| [1. Repository health reset](#1-repository-health-reset) | Restore a clean, current, all-green baseline |
| [2. Generated-code performance](#2-generated-code-performance) | Reach clang-cl and MSVC on `bench/` |
| [3. Safety without annotations](#3-safety-without-annotations) | Rust-class guarantees with nothing for the user to write |
| [4. Compilation speed](#4-compilation-speed) | The fastest thing that does this work |
| [5. Compiler memory](#5-compiler-memory) | A fraction of the resident set, at the same speed |
| [6. Compiler code health](#6-compiler-code-health) | Apply risk-free mechanical cleanup to swc itself |
| [7. Swag code and API quality](#7-swag-code-and-api-quality) | Make all of `bin/` an exemplary showcase of idiomatic Swag |

Campaigns 4 and 5 constrain each other on purpose: speed must not cost memory, and memory must not
cost speed. Run them one at a time, and let each one re-measure both numbers before claiming a win.

Campaign 1 runs directly on `master`. Campaigns 2 through 7 run in their own worktree, never in
the main checkout; each prompt states its own rule. For the isolated campaigns,
the worktree is not a formality. A campaign spans many rounds, keeps binaries and measurements
around, and reverts whole rounds; a shared tree picks up foreign uncommitted edits from other
sessions, and
MSBuild's incremental build then links someone else's in-flight code into the binary being
measured. The failures that produces look exactly like the bug the campaign was chasing.

---

## 1. Repository health reset

```
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
Step 8 remains deferred until the secondary audit and final cleanup are complete. After any fix, rerun the
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
  4. `bin\swc.exe tools\tests.swgs dm --all-cfg` - the same five-rung campaign in both target
     configurations.
  5. Rebuild `swc.exe` with the Release solution configuration using MSBuild `/t:Rebuild`
     to establish the initial baseline from freshly compiled C++ objects.
  6. `bin\swc.exe tools\tests.swgs` - the full Release validation campaign. Do not add a Release
     `--all-cfg` pass; the repository workflow deliberately reserves all-config coverage for
     DevMode.
  7. `bin\swc.exe tools\vsix.swgs` - refresh and package the VSCode extension with its documented
     Node.js/vsce prerequisites, then inspect the package result.
  8. LAST: run `bin\swc.exe tools\vault.swgs dm` with the bundled signed WinFsp runtime and the
     required Windows elevation (UAC); no prior machine-wide WinFsp installation is required.
     This integration is intentionally outside tests.swgs and is part of a genuinely full pass.
     Start it only after steps 1 through 7, all fixes and affected reruns, the final backlog and
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

CLEAN THE TREE BEFORE THE FINAL SWAG VAULT INTEGRATION

After validation steps 1 through 7 and before step 8, classify and remove temporary material created
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
backlog entries removed/moved/updated, documentation regenerated, formatting performed, temporary
targets removed, and any external blocker. The final statement "ready for new work" is allowed only
when every end condition above is true.
```

---

## 2. Generated-code performance

```
You are running a long optimization campaign on the swc backend. Read AGENTS.md and the skills it
points to first, then backlog/compiler.core.md, backlog/compiler.optimization.md, and bench/README.md.

WORK IN A SEPARATE WORKTREE; MERGE EACH VALIDATED BATCH

Do not run this campaign in the main checkout. Create an isolated worktree on a branch:

  git worktree add -b generated-code-performance ../swc-perf HEAD

This is not hygiene, it is measurement validity. A shared tree picks up foreign uncommitted edits
from other sessions, and MSBuild's incremental build then links that in-flight code into the
swc.exe you are timing - so a number moves and it is not yours. It also lets you abandon a whole
round with one checkout instead of unpicking it, which you will do often here. Keep each successful
optimization in a reviewable commit and merge every validated batch into local master. Integrate
concurrent master changes before merging; resolve conflicts and rerun the affected checks. Do not
leave validated batches accumulating only in the worktree.

START OPTIMIZING IN THE FIRST HALF HOUR

Build the compiler in the worktree and go straight to THE LOOP. Nothing comes before your first
change. The entry point of this campaign is one comparison - what clang-cl and MSVC emit for a hot
loop against what we emit for the same loop - and that comparison needs a compiler and two dumps,
not a validated tree.

Do NOT open with a baseline test ladder or a baseline bench campaign. Both are hours of machine
time spent answering a question you do not have yet, and the emitted code answers the question you
do have for free. Before your first change specifically:

  - Do not run tests.swgs, in any configuration.
  - Do not record a bench campaign.
  - Do not build measurement harnesses, per-configuration sweeps, or sentinels for failures you
    have not seen.

Validation is triggered by having something to validate; RULES says what to run then. The clock is
needed later than it looks, because step 6 judges on emitted code - so record the baseline campaign
in the same session as the campaign it is compared with, not before the work starts.

If a rung is already red when you do run it, name it in a sentence and move on: it is pre-existing
and it is not yours.

GOAL

Bring the code swc generates to the state of the art: match clang-cl and MSVC on every task in
bench/, on a machine where all three are measured in the same campaign. Concretely:

  - No task slower than 1.25x the FASTER of clang-cl and MSVC.
  - Geometric mean across all tasks at or below 1.15x that same best-of-both.
  - No task regressed, ever, at any point in the campaign.

This is the only thing being optimized here. Compile time is not a competing goal in this
campaign - see RULES.

Where it stands, campaign 20260806-174758 (run ms, lower is better):

  task      swag    clang-cl  msvc    swag / best-of-both
  chacha     1.71     1.23     1.58     1.39x
  csvagg    25.86    16.20    16.31     1.60x
  dijkstra  35.94    38.21    25.91     1.39x
  leven     18.16    11.84    16.24     1.53x
  raytrace  14.81     9.40     9.27     1.60x
  sha256     3.20     2.05     2.39     1.56x
  wordfreq  65.72    47.55    52.83     1.38x
  geometric mean                        1.49x

That table is one campaign on one machine, so read it as a starting order and nothing more: it says
which task to open, and your own campaign overrides it the moment you record one. Do not re-measure
it first. Every task in it sits between 1.38x and 1.60x, so whichever one you open has a real gap
waiting, and that gap is visible in the emitted code - two dumps, not twenty-five minutes.

THE LOOP

Pick the task with the worst ratio that you have not already exhausted, then:

  1. Read the assembly clang-cl AND MSVC produce for that task before you read ours. It is the
     answer sheet: it tells you what the win actually is, and it has repeatedly turned out to be
     something other than the transformation that looked obvious from our side (it does not
     vectorize the ChaCha rounds at all - it keeps sixteen words in sixteen registers). Read both:
     clang is not the best on every task, and where the two agree there is nothing left to decide.

       clang-cl /nologo /O2 /EHsc /std:c++20 /FA /c bench\src\cpp\<task>.cpp
       cl       /nologo /O2 /EHsc /std:c++20 /FA /c bench\src\cpp\<task>.cpp   (from vcvars64)

  2. Dump our micro code for the same function and find the specific difference: instruction
     count, memory operations in the loop, spills, dependency chain length. Name the mechanism
     before you touch a pass. Copy the task's swagnat source, add `#global #[Swag.PrintMicro]`,
     build it with the configuration the bench uses, and strip the ANSI colour before reading.
     Two traps in that dump, both of which invent loops that do not exist: instruction references
     RESTART at every function, so the map from a jump target back to an instruction has to be
     rebuilt per function; and a jump's target is the LAST number on its line, because the operand
     text also carries the width (`b32`), and 32 is a live reference often enough to matter.
  3. Implement the smallest change that addresses that mechanism, in src/Backend/Micro/Passes
     or the encoder. Formulate its eligibility from general properties of the code, such as
     data flow, aliasing, loop structure, and estimated work saved. Do not encode benchmark
     names, their exact constants, or thresholds chosen solely to fit one example. Check at
     least one unrelated input that has the same structure and one that must remain unchanged.
  4. Re-dump and re-count the same loops. This is the inner loop of the campaign and it costs
     seconds - one build, one count. Iterate here, not on the clock. Compare per loop and never on
     a total: an outer loop's span contains its inner loops, so a saving inside one shows up as a
     loss outside it.
  5. Validate correctness once the counts say the change is real, not before. Run the focused test
     that exercises the changed behavior, then draw one additional test at random from a different
     area. Use a different additional test for each batch: draw without replacement until the pool
     is exhausted, then reshuffle. Record the draw and both results. Select the smallest relevant
     compiler configuration using validate-swag-changes. Run a broad regression campaign roughly
     every five validated batches, and sooner when a shared boundary or a failure calls for it;
     include the appropriate DevMode, configuration, Release, and script coverage there. Do not
     run the full suite after every small optimization. A checksum mismatch in bench means you
     measured nothing.
  6. Judge the change against clang-cl and MSVC's output, not against the clock. The clock on this
     machine drifts more than most single changes are worth (two campaigns of the SAME binary
     measured a geometric mean of 1.41x and 1.54x, and drift inside one sweep reached +37%), and
     the context factor does not remove it. So: a change that provably moves the emitted code
     toward what the best compilers emit is kept even when the measurement is flat or slightly
     negative. They are right; matching them comes first, and beating them comes later.
     What "provably" means here is the per-loop count, which is deterministic: instructions and
     memory operations per iteration of each hot loop, before and after, next to the same loop in
     clang's assembly. A change is only reverted when the emitted code is not better - not when the
     benchmark fails to see that it is. Static proof plus correctness validation is sufficient to
     keep and merge a batch; no elapsed-time measurement is required. Small individual gains may
     become visible only after several batches. Name any enabling step and its follow-up.
  7. Use a quick timing sweep only when a tradeoff remains unresolved after static analysis:
     cd bench && py driver.py --tasks <task> --quick --swc-cores 6. Treat timings under changing
     machine load as exploratory. Partial sweeps are never recorded.
  8. Record a full benchmark campaign periodically across accumulated batches, not after each one:
     swc tools\bench.swgs --label "what changed". When comparing elapsed time, record its baseline
     in the same session. A full benchmark is not a prerequisite for merging a statically proven
     improvement.
  9. Commit and merge the validated batch into local master, then bring the worktree branch up to
     date before starting the next batch. Preserve unrelated changes on master.

Between some batches, audit an existing micro pass or backend decision, even if the current task
does not use it. Inspect its guards and thresholds, identify the general property that justifies
them, and compare an unrelated input with the same property against one that lacks it. Rework a
decision that only fits the benchmark examples as its own validated batch. Record the audit and
resume the next optimization; do not turn every batch into a full backend review.

DO NOT STOP AT THE FIRST FAILURE

Most of these experiments will fail. That is the normal shape of this work, and three of the
entries already in backlog/compiler.optimization.md are failed attempts written down so the next
one does not repeat them. When something does not work:

  - Revert it cleanly.
  - Write down what it ruled out, with the measurement, as a compiler.optimization.NNN entry in
    backlog/compiler.optimization.md (allocate the next file-scoped identifier as backlog/README.md states).
  - Take the next hypothesis from the same mechanism, or move to the next task.

The campaign ends when the goal above is met, or when you have run out of hypotheses on every task
- meaning three consecutive rounds across the whole task set left the emitted code no closer to
what clang-cl and MSVC emit. It does not end because one pass turned out to miscompile, one idea
lost 2%, or one task resisted.

RULES

  - Correctness first, always. Each batch needs its focused test and a rotating random test from
    another area before merge. Run the broader regression campaign periodically, and before
    trusting a full benchmark record. A pass that miscompiles under the JIT but passes unit tests
    is a known failure mode; include swc tools/scripts.swgs dm when the change can affect it.
  - Generated-code quality outranks compile time in this campaign. A backend optimization that
    works is never reverted because it costs compile time: generating better code legitimately
    takes longer, and campaign 4 is where compile time is bought back. Measure the cost, say it
    explicitly, and then make the implementation cheaper - a slow analysis is a slow analysis, not
    a reason to give up the optimization. Only a change that is BOTH slower to compile AND not
    better in the generated code gets reverted.
  - Never change what a bench task computes. That silently resets the history.
  - Bench tasks expose missed general optimizations; they are not special cases to recognize.
    Keep a change only when its rule can benefit ordinary user code with the same proven
    structure, and explain that rule independently of any benchmark.
  - When timing is needed, A/B two swc.exe binaries by CPU time, alternating order and sampling
    before the process exits. Do not reject a statically proven improvement because noisy elapsed
    times fail to resolve a small gain.
  - Leads you cannot chase now go in backlog/compiler.optimization.md with evidence and a concrete `Next:`
    step. If the evidence establishes implementation work, update that entry in place.

REPORT

After each round, one table: what you tried, before/after per-loop instruction and memory counts,
the focused and rotating test results, the merged commit, and why it was kept or reverted. Include
timings only when useful and credible. At the end of the campaign, give the new ratio table next to
the one above when a full campaign has been run.
```

---

## 3. Safety without annotations

```
You are running a long campaign on Swag's safety guarantees. Read AGENTS.md and the skills it
points to first, then backlog/compiler.safety.md, backlog/compiler.core.md, and the language
reference page bin/reference/modules/language/src/013_004_borrowing.swg, which states what the
language currently guarantees.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-safety HEAD

A new check reshapes what the whole tree compiles to, and you will revert entire rounds. An
isolated tree makes that one checkout, and it keeps foreign uncommitted edits from other sessions
out of the binary you are sweeping with - otherwise a hit you are triaging may come from someone
else's in-flight code rather than from your check.

Know the trap that comes WITH a worktree, because it has already cost a session: a scratch module
compiled with swc test -d <dir> resolves swag@std OUTSIDE the worktree, so it silently measures the
main checkout's standard library rather than yours. Any probe of behavior that crosses a module
boundary has to live in bin/unittests inside the worktree.

Before the first change, build and run the full test sequence AT BASELINE in the new worktree and
record the result. Any failure there is pre-existing, not yours.

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

For each check, in this order, and do not skip step 1:

  1. Write the tests first, both halves. The positives that MUST fire, in bin/unittests/sanity,
     and - this is the half that decides whether the check is usable - the negatives that must
     stay SILENT: an interface or pointer to the value itself, a method that only reads or assigns
     fields, a view rebound after the container grew, a container of views whose owner outlives
     them. A check with no negative tests is a check that will be turned off.
  2. Implement the smallest analysis that passes both halves.
  3. Sweep the whole tree for false positives, and mean the whole tree: swc tools/build.swgs,
     swc tools/std.swgs, swc tools/apps.swgs, swc tools/examples.swgs, swc tools/reference.swgs. The baseline is zero
     hits. Every workspace being clean today proves nothing, because nothing fires - the sweep only
     becomes evidence once the check works.
     A 'build' sweep is HALF a sweep: it never compiles the '#test' bodies, and a quarter of the
     standard library's interesting code lives there (Array's self-append test is where the first
     false positive of the invalidation check turned up, long after build.swgs came back clean).
     Sweep with 'test' as well, or just run swc tools/tests.swgs dm and read its first failure.
  4. Triage every hit, one at a time, into exactly one of two buckets: a real defect in bin/ (fix
     it, it is a genuine find) or a false positive (fix the analysis). There is no third bucket.
  5. Never silence a false positive by narrowing the check until it stops firing. That is how a
     check ends up complete and useless, firing on nothing. If a shape genuinely cannot be judged,
     say so as a finding and leave the check firing on what it can prove.
  6. swc tools/tests.swgs dm, then --all-cfg, then the Release sequence.

DO NOT STOP AT THE FIRST FAILURE

A new check that lights up forty call sites across bin/ has not failed - it has just started. Work
the list down. Expect several rounds where the analysis gets weaker before it gets stronger, and
expect at least one shape that needs a piece of information sema does not currently keep. When
that happens, the answer is usually to extend the summary that already crosses module boundaries
(#[Swag.BorrowSummary]), not to give up on the shape.

A round ends when its class is caught, the whole tree is clean, and what the language guarantees is
written down in the reference. It does not end because a check was noisy, because one shape needed
information that was not there, or because a sweep came back with hits.

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
You are running a compiler-speed campaign on swc. Read AGENTS.md and the skills it points to first,
then compiler.core.004, compiler.core.030 and compiler.core.056 in backlog/compiler.core.md and
compiler.optimization.029, compiler.optimization.039 and compiler.optimization.045 in
backlog/compiler.optimization.md. The last two carry the 2026-09-23 measurements and, as important,
the approaches that were tried there and measured as worth nothing.

The hello-world target below predates the runtime's growth: bin/runtime went from 5 260 to 8 629
lines between August and September and a hello world pays for all of it, which is compiler.core.030
rather than a compiler regression. Re-measure the four workloads before trusting any number here.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-speed HEAD

Every claim in this campaign is a timing, and a timing taken in a shared tree is worthless: foreign
uncommitted edits from other sessions get linked into your swc.exe by MSBuild's incremental build,
and a second build running on the same machine moves the number by more than anything you will
change. The levers below are also large, staged rewrites - a module interface format, a caching
layer - which need somewhere they can be half-finished without blocking anyone.

RELEASE COMPILER ONLY

Build, validate and measure only the Release compiler, `bin/swc.exe`. Do not build, invoke or run a
campaign through `bin/swc.dm.exe`; DevMode compiler behavior and timing are outside this campaign.
Before the first change, rebuild `swc.exe` from source, run the full Release test sequence at
baseline with that executable, and record every compilation workload's time with it once the
instrument below exists. Those are the numbers every later round is measured against.

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

Targets, all on this machine, all re-measured before you start. The readings below are from
2026-09-23 with Release 0.1.1056, six workers, minimum of five runs on a quiet machine:

  - std/core rebuild (360 files): 2.63 s. Target under 1.0 s.
  - Warm no-op build of the same: 50 ms. Guardrail under 100 ms; not an optimization target here.
  - Edit one file in core, rebuild: 2.41 s. Use it to expose repeated compiler work, but do not
    solve it with cache or invalidation changes in this campaign.
  - Hello world, source to linked executable: 211 ms. Target under 50 ms.

The hello-world reading is far above the 89 ms this prompt used to quote, and none of that is a
compiler regression: see compiler.core.030. Re-measure all four before trusting any of them.

For context on where the bar already is, from campaign 20260806-174758: swc builds the bench tasks
in 93-132 ms against clang-cl's 481-647 ms and rustc's 425-585 ms. This campaign is not about
beating them. It is about the loop a person actually sits in.

START BY VERIFYING THE INSTRUMENT

Do this before any optimization; nothing below can be judged without it, and it is compiler.core.004
in backlog/compiler.core.md.

The campaign must measure a full core rebuild, a warm no-op, a one-file-touched rebuild and a hello
world source-to-linked-executable build. Verify that all four workloads still run through
`bin/swc.exe`, record wall time and peak working set, and preserve the same normalization in
history.json before trusting any optimization result.

Use `bench/compile.py --swc bin/swc.exe --swc-cores 6 --admit --only core_rebuild,core_noop,core_touch,hello_build`
for fast iteration between campaigns. It does not record results; the full benchmark campaign owns
the durable history.

Use external profilers for per-stage investigation. Do not add optional counters, allocation
tracking, or profiling-only branches to the compiler: the benchmark campaign owns stable wall-time
and peak-working-set measurements, while focused external traces answer transient questions.

For parallelism work, record one-worker and capped multi-worker wall/CPU measurements on the same
clean workload. Name the serial fraction or contended primitive before changing it, and require
better scaling rather than merely shifting work between threads. Never exceed the repository's
per-process worker cap or the measured machine-load admission rules.

THE LOOP

  1. Profile the target workload. Name the stage that costs, with a number.
  2. Form one hypothesis about why, and predict what the fix should buy before you write it.
  3. Implement the smallest version of it.
  4. Measure against the prediction. A fix that lands far off its prediction means the model was
     wrong - go back to step 1 rather than keeping an accidental win.
  5. Confirm the result with order-alternated baseline/candidate runs. Require wall and process CPU
     to agree before claiming a measured speedup; a wall-only result under changing machine load
     does not support a performance percentage.
  6. Build `bin/swc.exe` in Release and run the smallest focused tests and concrete consumers that
     exercise the changed behavior, following validate-swag-changes. Do this for every batch. Do not
     rerun the full repository sequence for each batch: it consumes the iteration time needed to find
     the next improvement. Rebuild Release from source and run the full Release sequence at spaced
     milestones, after a high-risk cross-cutting change, and once more before the final report.
     Do not add a DevMode build or `dm` test pass.
  7. Record the changed internal stage, prediction, measurements, memory effect and validation.
  8. Commit the verified optimization and fast-forward it into `main` before starting the next
     batch. "Verified" includes either a repeatable measured win, or a correctness-certified
     structural improvement that demonstrably removes work, allocation, copying, contention, or a
     worse complexity class without a measured regression. For the latter, record "below the
     measurement floor" and make no percentage speedup claim. Revert only changes that are wrong,
     regress a guardrail, fail their structural proof, or add complexity that the evidence does not
     justify.

OPTIMIZE THE COMPILER, IN THIS ORDER OF EVIDENCE

Choose the next item from the hottest measured internal compiler cost, not from this list's order:

  1. Lexer and parser: byte/token scanning, source traversal, token storage, hashing, allocation,
     repeated decoding and syntax-tree construction.
  2. Semantic analysis: symbol and type lookup, overload/generic work, substitute chains, repeated
     AST walks, compile-time dependency discovery and JIT preparation.
  3. Scheduling and synchronization: job granularity, queues, wakeups, barriers, mutex/RW-lock
     contention, false sharing and serial critical paths. Demonstrate scaling at several worker
     counts and preserve deterministic compiler behavior.
  4. Lowering and backend: `CodeGenJob`, Micro construction, SSA construction, pass-manager
     convergence, repeated analyses, optimizer data structures, register allocation, instruction
     selection, encoding and object construction.
  5. Allocation and locality inside those phases: reuse capacity, shrink hot records, release
     phase-local storage and replace pointer-heavy structures only when a profile attributes the
     cost. Reject memory wins that cost CPU and CPU wins that materially regress peak memory.

Optimize algorithms and implementation, not generated program quality. If a backend change alters
emitted code, prove the code is equivalent and benchmark generated-code quality separately before
accepting the compile-time gain.

DO NOT STOP AT THE FIRST FAILURE

Compiler hot paths are mature, so many valid improvements will land below the noise floor. That is
not grounds to remove better code: retain a correctness-certified change when its mechanical proof
shows less compiler work, allocation, copying or contention and the measurements show no regression.
Label it honestly as below the measurement floor. Revert speculative rewrites, unjustified
complexity, and regressions. Keep batches small enough that either the measured gain or the
structural proof has one credible cause.

The campaign ends when the compiler-speed targets are met and both guardrail workloads remain
green. It does not end because one internal optimization avenue turned out to be harder than it
looked.

RULES

  - Never trade correctness for speed. Every retained batch passes its focused boundaries; the full
    Release sequence must be green at campaign milestones and before the final report.
  - Never trade generated-code quality for compile speed without measuring both. Run bench.
  - Never trade memory for speed without measuring both - campaign 5 owns that number and a
    regression there is a regression here.
  - A measurement taken once is a guess. Medians over order-alternated runs, or it is not a number.

REPORT

The four targets as a table, current versus target, refreshed every round. Under it, what changed
and what it bought.
```

---

## 5. Compiler memory

```
You are running a memory campaign on swc. Read AGENTS.md and the skills it points to first, then
backlog/compiler.core.md compiler.core.005.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-memory HEAD

Peak working set is the number this campaign lives on, and it is contaminated by anything else
happening in the tree or on the machine: foreign uncommitted edits linked in by MSBuild's
incremental build change what the compiler allocates, and a second build running concurrently
changes what the OS reports. You will also free things early and crash the compiler on purpose -
that belongs in a tree nobody else is standing in.

Before the first change, build and run the full test sequence AT BASELINE in the new worktree, and
record baseline peak memory AND wall time for every workload there. Both, always, from the start:
the constraint of this campaign is that one moves and the other does not.

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

START BY MAKING THE NUMBER ATTRIBUTABLE

There is no per-subsystem memory accounting today - only an OS peak. The split between AST, types,
symbols, constants and Micro is currently UNKNOWN. Capture that split with an external heap
profiler against the exact campaign workload; do not add per-allocation tracking or optional
profiling branches to the compiler. Then attack what the trace shows, not what it seemed like.

TWO SUSPECTS WORTH CHECKING EARLY

Both are already written down and neither is confirmed:

  - Nothing is released between stages. Post-codegen, the whole AST and every Micro function are
    probably still resident for the entire module.
  - Per-function Micro state is retained for the whole module rather than freed as each function
    finishes.

Confirm or kill each with the accounting before writing a fix.

THE LOOP

  1. Measure peak and the per-subsystem split on the target workload.
  2. Name the largest attributable block and why it is alive at peak.
  3. Free it earlier, store it smaller, or do not build it at all - in that order of preference.
     "Do not build it" is usually the real answer and usually the one that gets skipped.
  4. Re-measure peak AND wall time. A memory win that costs speed is not a win here; the whole
     constraint of this campaign is that both hold.
  5. swc tools/tests.swgs dm, --all-cfg, Release sequence.
  6. Record both numbers in the campaign history.

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
  - Compile time is a hard constraint. Measure it every round, medians over order-alternated runs.
  - The runtime allocator's arenas are never returned to the OS by design. Understand that before
    reading any peak: a fix that only reduces allocation churn may not move the peak at all.
  - Coordinate with campaign 4 lever 4: the parallel module scheduler multiplies peak memory by
    the number of concurrent modules, so this campaign gates that one.

REPORT

Peak memory per workload as a table, current versus target, next to wall time for the same
workload - always both, so a trade is visible the moment it happens.
```

---

## 6. Compiler code health

```
You are running a mechanical code-health campaign on the swc compiler itself. Read AGENTS.md and
the skills it points to first, especially modify-swag-codebase,
modify-swag-codebase/references/cpp-coding-rules.md, and validate-swag-changes. This is an
implementation campaign, not an audit, but its safety boundary is absolute: make only changes whose
semantic equivalence can be established directly from the source. If a proposed improvement needs
design judgment, changes a contract, or carries any plausible regression risk, leave it unchanged
and report it as outside this campaign.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Record the starting commit and status, then create
an isolated branch and worktree from that exact commit:

  git worktree add -b codex/compiler-code-health ../swc-compiler-code-health HEAD

Never copy uncommitted changes from the main checkout into it. Keep temporary reports under the
ignored .tmp directory and keep generated output out of the final diff.

SCOPE

Restrict edits to project-owned compiler and support code under src/ and the project files needed
to describe it. Exclude vendored code, generated output, language behavior, public module APIs,
diagnostic wording, command-line behavior, serialized formats, ABI, runtime contracts, cache
formats, and build-system semantics.

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
    real defect and you reduce and report that separately.
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
hot-path work. Do not fix a behavioral defect as part of this campaign: reduce and report it for a
separate change with its own regression test.

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

THE LOOP

For each batch:

  1. Read every affected declaration, definition, include path, and caller before editing. State
     the equivalence argument and the exact dependency or duplication being removed.
  2. Make the smallest complete edit. Add direct includes to real users before removing a
     transitive include. Keep lightweight types by value; do not hide real layout dependencies.
  3. Search the whole repository for every renamed symbol, moved type, removed include, helper, and
     project entry. Update all exact references in the same batch.
  4. Inspect the diff immediately. Reject unrelated formatting, line-ending churn, reordered code,
     or an edit whose safety now depends on an assumption not visible in the source.
  5. Compile or run the narrowest validation boundary that can detect a mistake in the batch. If a
     failure reveals that the edit was not purely mechanical, revert that edit instead of widening
     the campaign into a behavioral fix.

Prefer small reviewable batches. A mechanically safe campaign may be broad in aggregate, but every
individual transformation must remain locally obvious.

VERSION AND VALIDATION

Any campaign that changes src/ increments SWC_BUILD_NUM once in src/Main/Version.h, not once per
file. Before every compiler build or project test, follow the machine-load admission and compiler
worker limits in modify-swag-codebase. A separate worktree does not provide separate machine
resources.

Select validation from the final diff using validate-swag-changes:

  - Parse the Visual Studio project files after changing their entries or filters.
  - Build DevMode after the final source batch.
  - Also build Release when the campaign crosses compiler architecture, shared headers, conditional
    compilation, or source sets; otherwise do not add Release by habit.
  - Run the focused C++ or compiler suite boundaries that exercise code moved or mechanically
    refactored. Include-only and comment-only batches do not justify unrelated behavioral suites.
  - Do not run performance measurements for a purely mechanical cleanup. The campaign is invalid
    if an edit needs benchmarking to establish that it is safe.

After the last edit, run git diff --check, inspect git status including ignored test outputs, verify
that every new header is present in the project and filters, and remove temporary material. Detect
and restore files whose only change is line endings.

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
  - SWC_BUILD_NUM is incremented exactly once when required and the worktree contains only the
    intended code-health changes.

Do not claim completion for findings deliberately left outside the safety boundary. They are not
failures of this campaign; list them separately without implementing them. Duplication is not one
of them: a surviving copy is a failure of this campaign unless a contract, a layout, or a
behavioral difference genuinely blocks it, and the report must name which.

REPORT

Report the worktree path and branch, starting commit, coherent cleanup batches, important include
or dependency reductions, comments added or removed, internal renames, code reductions, skipped
non-mechanical findings, SWC_BUILD_NUM change, files changed, and every validation command with its
result. Report structural dependency counts when useful, but no timing or memory measurements.
```

---

## 7. Swag code and API quality

```
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

WORK IN A SEPARATE WORKTREE

Record the starting commit and status, then create an isolated branch and worktree:

  git worktree add -b codex/bin-quality ../swc-bin-quality HEAD

Do all campaign work there. Preserve unrelated local changes and do not copy uncommitted changes
from the main checkout. Use the worktree's bin/swc.dm.exe or bin/swc.exe explicitly so its runtime
and standard library are the ones being validated. Follow machine-load admission before every
build and test, and cap both tool compilation and child compiler invocations at six workers.

COVER ALL OF BIN/

Inventory the actual tree, including every project-owned .swg and .swgs source, module descriptor,
and public API. Cover runtime, every standard module, every application, examples, standalone
scripts, executable language-reference pages, compiler suites, module tests, and test helpers.
Discover additional directories from the tree instead of treating this list as exhaustive.

Keep a coverage table under the ignored .tmp directory with each area, reviewed files and API
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
capability, investigate the cause. Fix understood, relevant platform defects with their focused
regression coverage; do not spread local workarounds across bin/. Compiler source edits require
SWC_BUILD_NUM to move, and surface syntax changes require reference and editor updates.

For an unresolved design decision or a defect that needs separate investigation, search the whole
backlog, then update or create the owning domain entry with concrete evidence and a next action.
Keep the finding visible in the coverage table. Recording a defect does not make that area perfect
or the campaign complete; report the exact remaining limitation.

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
