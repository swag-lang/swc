# Campaign Prompts

Seven campaigns, one prompt each, ready to copy into a fresh session. These are not individual
tasks: each one is a target that takes many rounds to reach, and each prompt is written to keep an
agent working through the rounds instead of stopping at the first thing that does not work.

Each prompt names the goal, the evidence to collect, the loop to run, the rules that must not be
broken, and — most importantly — the condition under which the campaign is allowed to end.
Prompts 2 through 7 use the shared working protocol below; copy-pasting one of them into a fresh
session works because it explicitly points back to that protocol. Numbers quoted below are
historical context unless a prompt says otherwise; re-measure them when a campaign needs them,
and use a fresh source inventory for code-quality campaigns.

## Backlog policy for every campaign

The backlog is a shrinking list of unfinished work, not a campaign diary. This rule applies to all
seven prompts, including campaign-specific protocols below. Keep each entry focused on one
unresolved outcome and the minimum evidence needed to choose its next action.

- Add a new entry only for a new, concrete, actionable issue that remains unresolved; search the
  backlog first and do not duplicate an existing outcome.
- Update an existing entry only when new evidence clarifies or changes the next action for work
  that is still unresolved. Keep only the information needed to continue that work.
- Delete an entry as soon as its outcome is complete, disproved, or no longer wanted. Do not append
  repeated findings, completed work, dates, validation history, or campaign progress to keep it
  alive. Git and the campaign report preserve history.
- If a campaign produces no material change to an unresolved entry, leave the backlog untouched.

`repo.prompts.md` holds reusable campaign instructions and current baselines, not per-session
findings. Put campaign results in their reports and Git history.

| Campaign | Target |
| --- | --- |
| [1. Repository health reset](#1-repository-health-reset) | Restore a clean, current, all-green baseline |
| [2. Generated-code performance](#2-generated-code-performance) | Reach or exceed comparable production compilers on representative workloads |
| [3. Safety without annotations](#3-safety-without-annotations) | Rust-class guarantees with nothing for the user to write |
| [4. Compilation speed](#4-compilation-speed) | The fastest thing that does this work |
| [5. Compiler memory](#5-compiler-memory) | A fraction of the resident set, at the same speed |
| [6. Compiler code health](#6-compiler-code-health) | Apply risk-free mechanical cleanup to swc itself |
| [7. Swag code health](#7-swag-code-health) | Review runtime and app-used standard modules, including APIs |

Campaign 6 cleans up swc itself; campaign 7 reviews `bin/runtime/` and the `bin/std/modules/`
modules used by shipped applications, in both substance and presentation. Semantic refactoring,
API quality, and visual readability belong to the same campaign and coverage inventory. A
formatter pass alone completes neither review; keep presentation-only edits distinct from
refactors, defect repairs, and contract changes so each receives the right evidence.

Campaigns 4 and 5 constrain each other on purpose: speed must not cost memory, and memory must not
cost speed. They may run concurrently in separate worktrees. Measure both numbers before
claiming a quantitative win.
Campaign 4 changes compiler work to reduce compilation time; campaign 6 improves the compiler's
source without changing that work. Assign an idea by its intended result: a faster compiler belongs
to 4, while a mechanically equivalent cleanup belongs to 6, even when both touch the same file.

### Shared working protocol (prompts 2–7)

Read and follow this entire protocol for any of prompts 2 through 7. Give each campaign its own
branch and worktree outside the main checkout, from the current `master` commit, placed beside
the main checkout as the `modify-swag-codebase` skill requires. Use a unique branch
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
no validation. Follow validate-swag-changes for every build or test.

Commit each retained, focused-validated batch in its worktree. Integrate the first validated code
batch into local `master` promptly, then integrate coherent groups at most every four to six
retained batches and before ending a work session with a validated gain. Include required tests and
documentation with the code. Merge the validated batch first, then synchronize the campaign worktree
for the next batch, following the integration order below. Keep routine observations in the final
report. Update the backlog only under the policy above; never merge a notes-only batch.

Rotate an unrelated focused check every few retained batches when it exercises a meaningful path.
Run broad suites, cross-configuration checks, whole-tree sweeps, and full measurements about every
five retained batches, after a change whose risk specifically calls for them, and before a final
claim that depends on them. They are not gates for every low-risk batch or intermediate merge. A
focused failure must be reduced and fixed before retention; do not carry a known regression into
`master`.
Keep `SWC_BUILD_NUM` unchanged for ordinary compiler changes. Isolate or clear affected caches
when an older binary's artifacts would make validation unsafe. Keep temporary logs and probes
outside the checkout, and use the checkout-local compiler.

Several agents may run different campaigns at once.
Integrate in this order:

1. Merge the committed, focused-validated campaign batch directly into local `master`. Allow a
   normal merge commit when the branches have diverged. Do not first pull, merge, or rebase
   concurrent `master` changes into the campaign branch, rebuild, or rerun tests merely because
   another agent advanced `master`. Preserve unrelated uncommitted work in the target checkout.
2. If the merge has conflicts, resolve them in the campaign worktree and run only the focused
   checks invalidated by those resolutions before completing integration. This is the exception
   to merging first. If `master` advances again, retry the merge; restart resolution and its checks
   only for new conflicts, without chasing every intervening commit with another validation cycle.
3. After the merge succeeds, synchronize the campaign worktree with the resulting `master` once,
   then start the next code batch on that combined base. Include affected integration checks in
   that next batch's focused validation; synchronization alone does not trigger an immediate
   rebuild or test round. Further concurrent commits wait for the next integration cycle.

Keep validation evidence tied to the revision actually tested: a conflict-free merge does not
prove the combined revision green. Investigate concrete failures when found and retain the broad
validation milestones above, without making them a gate for every merge.

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
Validate the repository on Windows first, then on native Linux. Build the Release compiler
and use it for all campaign builds and tests under bin/ with -bc release. Use the shared plan
once per host. Treat compiler executable and program configuration as independent choices
when diagnosing a failure.

Execution order

1. Prepare once.

   Read AGENTS.md, modify-swag-codebase, validate-swag-changes, and the applicable launcher
   guidance in tools/README.md. Work in the main checkout on master. Record the starting
   commit, git status, existing local changes, and toolchain versions. Preserve local work.
   Keep logs outside the checkout and reuse valid incremental objects and caches.
   Run tools\portability.bat once on Windows.

   Increment SWC_BUILD_NUM in src/Main/Version.h by one before the first build. Keep that
   number for both hosts and resumed sessions. Record each resulting Release compiler's hash.
   Use the checkout-local Windows compiler and a native Linux compiler built from the same
   committed sources. Keep each host's build outputs and caches separate.

2. On Windows, run shared step A to build the Release compiler and the bin/ workspaces.
3. Run repository maintenance once with the Release compiler. Rebuild only targets whose
   inputs changed during maintenance.
4. On Windows, run shared step B, resolve failures, run Windows integrations, and
   commit the validated batch on master. Prefix campaign commits with [prompt 1].
5. Run tools\linux.bat sync. Verify tools\linux.bat exec git rev-parse HEAD against the
   validated Windows commit. Linux starts after all required Windows checks pass.
6. On native Linux, run shared steps A and B, resolve failures and run Linux integrations.
7. Verify the final revision. For a late correction, commit the fix on master and sync it
   to Linux. Repeat only affected maintenance and validation checks on each host. If Swag
   Capture changed, finish with tools\apps.bat build swagcapture -bc release in the main
   checkout. Run git diff --check and git status --short --branch. Finish when all required
   checks apply to the final committed tree, all discovered defects are resolved, and
   master is clean.

When a host is unavailable, finish independent work on the available host and record
exactly which checks remain pending.

Shared build and test pass

   A. Build the Release compiler incrementally, then build std, examples, apps and reference
      in that order. Start with the aggregate commands below. The
      workspaces handle dependency builds, including the runtime. Test-only fixtures,
      scripts and expected diagnostics are covered at the test or smoke boundary that
      knows how to validate them.

   B. Run the functional and golden passes separately. The functional pass includes scale cases.
      Run lexer, parser, sema, jit, safety, sanity, native and workspace fixtures with the
      Release compiler. The launcher schedules C++ unit tests only with the DevMode
      compiler. Use those tests as a focused check for a suspected compiler defect.
      Headless fixtures always render on CPU.
      Clear any golden-continue override. Finish independent groups after a failure, then narrow
      the failing or unvisited scope.

   On Windows, resolve MSBuild from PATH or the Visual Studio installation.

     A. MSBuild.exe swc.sln /t:Build /m /p:Configuration=Release /p:Platform=x64
        tools\build.bat -bc release
     B. tools\tests.bat functional -bc release --keep-going
        tools\tests.bat goldens

   In WSL 2

     A. tools\linux.bat --release build
        tools\linux.bat exec python3 tools/tool.py <workspace> build -bc release
        Run the workspace command in order for std, examples, apps and reference.
     B. tools\linux.bat exec python3 tools/tool.py tests functional -bc release --keep-going
        tools\linux.bat exec python3 tools/tool.py tests goldens

   The WSL wrapper sets the compiler and runtime paths. The shared tool uses the Linux
   checkout's normal incremental outputs for both builds and tests. On a native Linux
   host, run the Python commands directly. Build with python3 tools/linux-build.py
   --build-dir <external path> --configuration release, copy bin/runtime beside the compiler,
   and set SWAG_PATH and SWC_COMPILER to the corresponding runtime and compiler paths.

Failure diagnosis and reruns

   Start each pass at the aggregate level. If it fails, use the existing output to find
   the failing workspace or compiler suite. Continue independent checks and collect
   failures before editing. The Windows aggregate build stops at the first failing
   workspace. Resume the unvisited workspaces with their aggregate build commands.
   After a failed test stage, use the runner output to identify any unvisited coverage.

   Narrow only as far as needed to reproduce and diagnose the failure.

   - For a workspace or suite, run tools\<workspace>.bat build|test -bc release, or
     tools\unittests.bat <suite> -bc release --keep-going.
   - For a module, run tools\<workspace>.bat build|test <module> -bc release.
   - For a file, append --test-file <path fragment> to a workspace test. For a standalone
     compiler-suite input, use --file-filter <path fragment> on unittests instead.
   - For a case, use an existing sufficiently narrow --test-tag within the selected file,
     or reduce the case in a temporary reproducer while retaining the failing boundary.
     Check that filtered runs actually select the intended input or test.

   Use the equivalent tool.py commands on Linux. Reproduce using the failing host and Release
   flags. If a compiler defect is suspected, switch only the focused reproducer to swc.dm.exe
   on Windows or swc.dm on Linux. Keep -bc release when testing the same generated program.
   If the failure may depend on the Release program configuration, use -bc devmode only for
   that focused comparison, with the Release compiler unless it is also suspect. Confirm
   the correction in Release and resume the campaign from the affected stage.
   Use assertions and runner status to validate tests. Keep test code free of prints, log
   checks and output files used as pass markers.

   Group failures by root cause. Fix them in batches, add focused regression coverage where
   needed, and verify the failing boundary first. Rebuild a compiler only when the batch
   changes its inputs, and use the existing incremental build. Rerun failed, newly
   unblocked, unvisited and invalidated work. A workspace-only fix ordinarily affects its
   own checks and any affected consumers. Broaden reruns when the change can reach shared
   behavior or the impact is uncertain. Keep independent green evidence. Investigate
   intermittent failures with a bounded reproducer. Review a golden mismatch before any
   promotion.

Host integrations

   Run these once per host, after its Release pass. Use a compatible graphical session for
   smoke, native application and OpenGL tests.

   On Windows, run these in order.

     tools\tests.bat smoke -bc release --keep-going
     tools\tests.bat integrations -bc release

   On Linux, run these in order.

     tools\linux.bat exec python3 tools/tool.py tests smoke -bc release --keep-going
     tools\linux.bat exec python3 tools/tool.py tests integrations -bc release

   The integration pass selects OpenGL, native host tests, application journeys and desktop input.
   The smoke pass checks bounded startup for examples and apps, plus scripts on Windows.
   Select individual targets to diagnose failures.
   Record missing prerequisites as blockers. Add a specialized integration when a
   discovered failure or changed contract needs it.

Repository maintenance

   - Run tools\format.bat, then clang-format on project-owned .cpp, .h and .inc files
      under src/, excluding vendored mimalloc. Review the diff and verify that a second pass
      of each formatter is idempotent.
   - Run tools\help.bat -bc release to generate std and reference help. Review the diff and
     verify idempotence with a second generation. On a Linux-only host, use Release format
      -d bin and doc --workspace <bin/std or bin/reference>
     --doc-output-dir bin/help --rebuild -bc release.
   - Review backlog entries and actionable TODO/FIXME/HACK/XXX markers. Keep the backlog
      limited to unresolved outcomes and remove completed or disproved entries. Clean only
      reviewed generated residue. Preserve canonical test output roots and pre-existing work.

Progress and final report

   Keep one progress row per aggregate command with its host, compiler, program configuration
   and status. Expand that row only for failures, blockers, or unvisited coverage. Record
   the current command and the next one. When reporting test counts, use runner evidence
   and count reruns separately. Keep validation checks separate from test-case totals.

   Report the final revision and build number, the result of each pass, the focused reruns,
   and any blockers. If work remains, record the exact next command and resume from it.
```

---

## 2. Generated-code performance

```
Read and follow the shared working protocol for prompts 2 through 7 in backlog/repo.prompts.md.
Read AGENTS.md, its applicable skills, and the open work in backlog/compiler.build.md,
backlog/compiler.codegen.md and backlog/compiler.optimization.md.

Improve the Swag backend until ordinary Swag programs reach or exceed comparable production
compilers. Choose work by its impact on real callers and by how widely the mechanism applies.
Aim for parity or better on each representative workload. Report reproducible losses
individually and claim a lead only when repeated measurements distinguish it from parity.

CHOOSE THE NEXT GAP

Start with a hot path in an existing application, standard module, runtime service or real
consumer. Use a current profile, an existing reproducible input or concrete missed code shape
to pick one cost and one hypothesis. Look at the whole executed path, including work done by
its callees. Prefer comparisons with existing implementations when they perform the same
operation under comparable contracts.

When a direct comparison is hard to isolate, write a small equivalent example in Swag and the
comparison language in an external scratch directory. Generate its inputs for this investigation.
Start with ordinary idiomatic source to see what automatic optimization can do. Keep the real
caller in the validation when a reduced example omits important data flow or register pressure.
Use independent inputs and another caller or code shape where the rule should apply. Try a
counterexample where it must not apply. Keep only durable regression tests for the language or
backend behavior in the compiler suites.

Rotate through integer and floating-point loops, irregular branches, SIMD, memory access,
aggregate values, allocation, native and foreign calls, and cross-module optimization. Cover
real lengths, data distributions, unaligned inputs, short tails and different alias relationships
when these conditions change the executed path. Preserve the program's observable behavior.

COMPARE PRODUCTION COMPILERS

Use current available production compilers for the operation and target. Compare GCC and
Clang/LLVM on Linux and MSVC and clang-cl on Windows where relevant. Include Rust, Zig, Go,
Swift or a managed runtime when its shipped code is a useful peer. Record exact versions,
flags, ABI, ISA, integer and floating-point policy, safety, allocation, reclamation and worker
count. Compare under matching contracts first. Report separately any tuned library, explicit
SIMD, different runtime or best shipping configuration that changes those contracts.
Describe missing tools or platforms precisely.

Verify the same outputs or checksums before comparing execution. Look at the final native
disassembly and use Micro to explain the Swag lowering. Identify the actual inlined or
out-of-line region, trip counts, dependencies, loads, stores, spills, calls and branches.
Weight the changed path by its executions. Check matching and mismatching inputs and shared
paths reached by the change. Instruction counts and assembly similarity alone do not establish
a speedup. A different algorithm, allocator or runtime can explain a product gap without
pointing to a backend rewrite.

WORK IN FOCUSED ROUNDS

  1. State the observed cost, the relevant compiler reference, the general property that
     could remove the cost, and the observable behavior that the property preserves.
  2. Preserve the baseline compiler and its adjacent runtime outside the checkout. Capture
     the baseline code of the target and the reachable hot paths relevant to the mechanism.
     Keep sources, options and inputs identical across Swag revisions. Force regeneration
     and isolate caches and output directories. Keep build and toolchain identities.
  3. Edit the responsible lowering, analysis, allocation, instruction selection, encoding
     or layout mechanism. Keep the proof general. Benchmark names, source locations and
     constants fitted to one sample cannot decide eligibility. Explain the analysis cost.
  4. Rebuild once for the coherent batch. Run the smallest focused correctness checks and
     verify output for the compared inputs. Inspect changed final code in the target,
     independent caller and counterexample, including reachable shared runtime paths,
     changes with equal counts and functions added or removed by inlining.
  5. Retain a batch only when it removes executed work or shortens a dependency on the hot
     path without a reproducible regression. Include an explicit trip-count weighting for
     any instruction, throughput, register or memory trade. Commit and integrate according
     to the shared protocol with a `[prompt 2]` prefix and the evidence in the commit body.
     Continue with another credible gap if the current mechanism does not help.

MEASURE AT USEFUL BOUNDARIES

Static evidence and correctness can justify landing a batch on a busy machine. Label that
result as unconfirmed until a runtime comparison resolves it. When useful, compare preserved
executables on the same host, using the same inputs and measurement boundary. Warm both
versions, pin comparable cores when possible, alternate the order, include unchanged-binary
controls and retain every sample with the host and toolchain details. Avoid overlapping
the timing with this session's builds and tests. Repeat a clear slowdown in an independent
block. Revise or revert a reproducible regression, including layout regressions established
from the emitted bytes and actual hot path.

At a session milestone repeat the selected real consumers and focused cases on the combined
revision when comparable timing is available. Reproduce commands and input generation in the
session report with the tested revisions, output checks, hashes, static work and sample
dispersion. Keep a case set fixed across any before/after comparison and report per-case
ratios before any aggregate. Record exactly which measurements remain pending.

Continue while the requested budget permits and there is a material, credible opportunity.
Use the requested cutoff. Leave the best validated revision integrated and identify pending
work. The backlog holds only open, actionable decisions. Keep completed investigations in
Git history and the session report.
```

---

## 3. Safety without annotations

```
Read and follow the shared working protocol for prompts 2–7 in backlog/repo.prompts.md.

You are running a long campaign on Swag's safety guarantees. Read AGENTS.md and the skills it
points to first, then backlog/compiler.safety.md, backlog/compiler.build.md, and the language
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

What is left is precision, and the live entries in `backlog/compiler.safety.md` are the
authority. Re-read that file before choosing a round.

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
     the rule works across the repository, sweep the whole tree for false positives: tools/build.bat, tools/std.bat, tools/apps.bat, tools/examples.bat, and tools/reference.bat. Include test bodies: a build-only sweep misses them, including the
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
an initial baseline, A/B timings, a profiler, or a broad workload check at milestones or before
integration. Collect elapsed-time, CPU and peak-memory measurements in a separate focused
investigation when they are needed. If a change needs timing to establish that it saves work, discard it and
try a change whose saving can be proved from the code.

You are running a compiler-speed campaign on swc. Read AGENTS.md and the skills it points to first.
Search `backlog/compiler.build.md` and `backlog/compiler.optimization.md` for unresolved entries
about compilation time or compiler work. Confirm each lead against current code, and check Git
history and any available prior reports before repeating an experiment. Start editing compiler
code after this review.

DEVMODE COMPILER ONLY

Build and validate planned speed work only with the DevMode compiler, `bin/swc.dm.exe`.
Use an existing recent green DevMode campaign as the correctness reference. Do not build
`bin/swc.exe` for this campaign; it does not measure compilation timings.

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

Targets and historical context from the 2026-09-25 comparison with Release build 1150
and six workers:

  - Full `std/core` rebuild (360 files): 2.241 s. Target under 1.0 s.
  - Warm no-op build of the same: 42 ms. Guardrail under 100 ms; not an optimization target here.
  - Edit one file in core, rebuild: 1.935 s. Use it to expose repeated compiler work, but do not
    solve it with cache or invalidation changes in this campaign.
  - Hello world, source to linked executable: 126 ms. Target under 50 ms.

Use the historical values to select compiler work. A fresh quantitative comparison needs matched
revisions and inputs. Keep the generated program's runtime comparisons in prompt 2.

STRUCTURAL EVIDENCE

Use existing profiles to choose a path, then establish each saving from code: fewer traversals,
calls, allocations, lookups, or synchronization steps for equivalent inputs and output. Do not add
profiling-only branches to the compiler. Investigate uncertain timing, scaling, CPU and peak-memory
tradeoffs separately on the affected consumer when needed.

THE LOOP — PRIORITIZE CODE ITERATIONS

  1. Use a recent profile to select one costly internal stage. Give one concrete hypothesis and a
     predicted effect; spend minutes, not hours, on investigation before the first edit.
  2. Group related edits into a coherent code batch. Inspect the final diff for equivalent output
     and a clear reduction in compiler work, then rebuild DevMode once for the batch. Rebuild
     earlier only when compiler output determines the next edit. Discard an uncertain tradeoff
     rather than timing it in this campaign.
  3. Retain a structurally proven saving after its focused correctness check. Record the operation
     removed without assigning a percentage or claiming a measured speedup. At a milestone,
     review accumulated changes for hidden CPU, memory, and generated-code tradeoffs; send any
     change that needs measurement to its owning campaign.
  4. Before retaining a speed batch, use a focused DevMode-compiler check that exercises it.
     Broader DevMode checks follow the shared milestone and risk rules.
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
     investigate changes that depend on scaling measurements separately.
  4. Lowering and backend: `CodeGenJob`, Micro construction, SSA construction, pass-manager
     convergence, repeated analyses, optimizer data structures, register allocation, instruction
     selection, encoding and object construction.
  5. Allocation and locality inside those phases: reuse capacity, shrink hot records, release
     phase-local storage and replace pointer-heavy structures when existing evidence attributes
     the cost. Investigate uncertain memory/CPU trades separately.

Optimize algorithms and implementation, not generated program quality. If a backend change alters
emitted code, prove the code is equivalent and use static generated-code inspection; defer any
uncertain quality tradeoff to campaign 2.

DO NOT STOP AT THE FIRST FAILURE

Compiler hot paths are mature, so many valid improvements will land below the noise floor. Retain
a correctness-certified change when its mechanical proof shows less compiler work. Accumulate
these small savings and measure aggregate timing separately. Label an unmeasured
saving as structural, without a percentage claim. Revert speculative rewrites and unjustified
complexity quickly, then try the next idea.

The campaign can claim its structural work complete when no concrete statically provable compiler
saving remains. Report speed targets and guardrails as unverified until comparable measurements
are available. One difficult optimization avenue does not end this one.

RULES

  - Never trade correctness for speed.
  - Preserve generated-code quality by static inspection; leave uncertain tradeoffs to campaign 2.
  - Preserve memory behavior where code inspection can prove it. Investigate uncertain tradeoffs
    on the affected consumer separately.
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
backlog/compiler.build.md compiler.build.005.

Use the last accepted memory and compile-time measurements as context. Start with the highest
attributed memory cost and edit before launching a broad test or measurement run. When a retained
batch needs a quantitative comparison, measure its affected workload against a fresh baseline in
the same session, recording peak working set and wall time together.

GOAL

Make swc need a fraction of what it needs today, at the same speed. Memory is what bounds how many
modules can compile at once, and it is what makes the difference between a language you can run as
a script and one you cannot.

compiler.build.005 asks for a fresh six-worker DevMode `core` rebuild and hello-build peak
before choosing a reduction. Compare production compilers on equivalent real or temporary
sources when the artifact, toolchain state and work performed support the comparison.

Targets:

  - core rebuild under 250 MB devmode.
  - Hello world under 50 MB.
  - Use at most the peak memory of a comparable production compiler on matched source builds.
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

## 7. Swag code health

```
Read and follow the shared working protocol for prompts 2 through 7 in backlog/repo.prompts.md.

You are running the Swag code-health campaign for `bin/runtime/` and the standard modules under
`bin/std/modules/` that shipped applications use, directly or through module dependencies. Improve
both their substance and presentation, just as prompt 6 cleans up swc itself. Read AGENTS.md, then
the skills modify-swag-codebase, validate-swag-changes, write-idiomatic-swag-code and its
references/readability.md, design-swag-bin-modules, and write-swag-public-api-docs. Read
tools/README.md, backlog/README.md, and the relevant domain backlogs. Apply the application,
visual identity, theme, dialog, compiler message, and syntax-reflection skills whenever a batch
enters their scope. The shared protocol governs isolation, commits, integration, and defect repair
for the entire campaign, including presentation-only batches.

GOAL

Make the runtime and app-used standard modules the reference showcase for the Swag language, in
both substance and form. A reader should be able to copy its code and learn the best current
language idioms, clear design, safe resource handling, coherent APIs, and readable layout. This is
an implementation campaign: clean up, improve, refactor, simplify, and finish the code, its public
contracts, and the way it reads. An inventory of problems alone does not satisfy the goal.

Quality is judged by correctness, clarity, consistency, useful API completeness, visual reading
effort, and the code a caller actually writes. Shorter code is valuable when it expresses the
same intent more clearly; line count, uniform shapes, and use of the newest syntax are not goals
of their own. Keep already clear code unchanged; do not manufacture churn to demonstrate progress.

SCOPE: RUNTIME AND STANDARD MODULES USED BY APPS

The in-scope code is `bin/runtime/`, its tests and helpers under `bin/unittests/native/runtime/`,
and the transitive dependency closure of the `bin/std/modules/` modules imported by shipped
applications in `bin/apps/`. Determine that closure from application module descriptors and
sources, then follow declared and conditional imports among standard modules. Record the resulting
module list in campaign state so the scope is reproducible. The current shipped-app closure is
`core`, `pixel`, `gui`, `audio`, `video`, `truetype`, `net`, `screen`, `ogl`, `win32`, and `linux`;
recompute it if application or module imports change. Include each in-scope module's project-owned
implementation, module descriptor, public API and module-owned tests and test helpers. Use
application sources only to discover dependencies and check real caller contracts;
do not review or change application implementation.

Applications, examples, standalone scripts and tools, language-reference pages, compiler suites
other than the runtime-owned tests above, and standard modules outside the application dependency
closure are out of scope. Do not add them to active coverage. Discover source and test directories
within each included module from the actual tree; do not assume a fixed layout. Preserve each test's
purpose, including intentionally awkward or invalid fixture code.

Keep a coverage table outside every checkout with one row per source file, its area and API
families, separate semantic and visual review status, findings, retained changes, validation,
and remaining work. For each review dimension use pending, reviewed unchanged, changed and
validated, or excluded with a precise reason. Every project-owned source must receive both
reviews; a pattern search or formatter pass alone is not review. Read complete functions and
related operations, then their neighbours and module entry points. Inspect public declarations
together with implementations, documentation, tests, and representative callers. Inspect every
member of a repeated family before marking that family complete.

Classify generated sources, vendored sources, binary assets, fixtures, and compilation artifacts
inside the selected modules explicitly. Review project-owned generation inputs in those modules
and regenerate derived output through its owning tool. Do not hand-edit generated output. Preserve
upstream code and fixtures whose unusual form is intentional. Justify exclusions individually and
keep them separate from reviewed counts.

RESUME A PREVIOUS PASS

Keep durable campaign state in a session directory outside every checkout, such as
$env:TEMP/swc-code-health-YYYYMMDD. Store coverage.json and validation-summary.json there, with
the worktree, branch, current_commit, per-file review evidence, and exact validation commands and
results. Update both after every validated batch. On resumption, load the matching session state
before making a fresh inventory, even if its branch or worktree has been removed. Compare the
recorded revision and file contents with the current base; retain only evidence that still applies,
and return changed or uncertain files to pending in each affected review dimension.

If resuming an older swc-readability-* session, import its per-file visual evidence after checking
it against current sources. Its reviewed files still need semantic review, and its excluded
unittest files join the full inventory as pending; old formatter runs do not prove visual review.
Inspect any pending.patch against its recorded base before restoring it as unvalidated work.
If no prior state exists, record that this is a new pass. Keep campaign state and routine progress
out of the backlog, following the shared backlog policy.

PRIORITIZE BROAD VALUE, THEN REVIEW COMPLETE AREAS

Start from existing evidence and make a useful edit promptly, as required by the shared protocol.
Build the inventory incrementally; do not delay implementation for a whole-tree opening sweep.
Inspect recurring reading obstacles and existing formatter rules when they offer broad value.
Consider a global formatter improvement only when syntax and layout can decide it, authored
intent is preserved, and the pattern recurs across many files. Measure candidate counts and
inspect representative positive and negative cases before changing a rule. Inspect every changed
file and confirm second-pass stability afterward. Keep focused formatter regression coverage,
including single-line-argument-column-limit when affected. A formatter cannot choose business
phases, invent useful names, extract helpers, or judge whether a purpose comment helps.

Prefer broad, low-noise improvements over scattered cosmetic edits. Start deep reviews at public
APIs and important internal paths in the selected standard modules and runtime. Let concrete
defects and high-value evidence adjust this order without dropping any in-scope area from coverage.

WHAT TO IMPROVE - SUBSTANCE

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
  - API changes: make a deliberate before/after contract decision and assess compatibility. Update
    module-owned tests, documentation, and comments in the same batch. Use application call sites
    as read-only contract evidence; preserve compatibility for them, or report a required migration
    as blocked because application implementation is outside this prompt's scope. Do not leave
    half-renamed families or compatibility wrappers with no concrete requirement.
  - Teaching quality: code samples in in-scope module documentation must show the recommended way
    to solve their problem. Keep them small and complete, with correct failure handling and
    resource cleanup. Public module documentation must explain contracts, edge cases, and
    ownership, and use examples that compile against the final API. Replace stale or narrating
    comments with clear code or concise explanations of the reason behind a non-obvious choice.
  - Efficiency: remove demonstrably unnecessary copying, allocation, repeated work, or poor data
    structure choices. Measure changes whose performance depends on workload; preserve deliberate
    fast paths unless evidence supports the replacement. Do not trade clarity for speculative speed.

WHAT TO IMPROVE - PRESENTATION

  - Group related statements into paragraphs. Add one blank line when the purpose changes;
    remove blanks that scatter one calculation, initialization, guard group, or cleanup pair.
  - Give substantial phases a short, accurate purpose comment when it helps the reader breathe.
    Keep the comment attached to the following code. Remove obsolete or narrating comments;
    avoid banners, commentary quotas, and numbered descriptions of every statement.
  - Make long statements readable by breaking at argument, parameter, condition, or component
    boundaries. Aim near 100 columns and review lines over 120, with justified exceptions for
    indivisible literals, meaningful data rows, and imposed signatures. Layout changes must
    preserve every operator, parenthesis, operand, and their order. Do not split strings or
    change literal contents just to satisfy a width target.
  - Keep short, obvious accessors and delegations compact. Expand existing braced bodies when
    signature and body together become hard to read. Do not pack substantial logic onto one line
    merely because it is one statement or a neighbour is compact.
  - Keep sibling declarations of one purpose together; separate unrelated groups and let the
    formatter align them. A presentation-only edit preserves declaration order, useful names,
    and type boundaries. A deliberate reorganization belongs in a refactoring batch.
  - Re-read the entire function after formatting, then its neighbours and module entry points.
    Balance horizontal density against vertical sprawl. Return to difficult functions after a
    later batch to check that the layout still reads naturally. Do not oscillate between equally
    readable layouts. Names, width searches, and the optional readability rubric find candidates;
    none proves that a function has been understood.

DISTINGUISH THE KIND OF CHANGE

Presentation-only batches change whitespace, layout, and ordinary explanatory comments while
preserving logic. Renames, helper extraction, new locals or with blocks, expression-body rewrites,
reordered declarations or imports, and API changes are also in scope for this campaign, but they
are refactors or contract changes and require the corresponding review and validation. Keep
behavioral defect repairs in separate focused batches under the shared protocol. Do not disguise
a semantic change as formatting or defer a concrete defect to a separate visual campaign.

Swag layout and comments can be significant. Preserve token boundaries, source-sensitive macros,
#curlocation and line-number expectations, directive and attribute attachment, generated-code
inputs, documentation contracts, diagnostic markers, formatter controls, and fixture text.
An ordinary comment must not accidentally become documentation for another declaration. Preserve
literal bytes, including multiline strings, during layout changes. Equal non-whitespace text
alone does not prove equivalence: newlines can affect parsing and source locations. Revert any
cleanup whose equivalence is uncertain, then investigate its contract before attempting a refactor.
If a formatter blocks useful layout, reduce and fix its owning rule with focused coverage instead
of adding filler to defeat it.

THE LOOP

  1. Pick one cohesive area or cross-module API family from the coverage table. Read its full
     implementation and callers, establish the current contract, and identify semantic weaknesses
     and visual reading obstacles. Review complete functions and related operations.
  2. State the intended improvement and the narrowest validation that observes it. Distinguish
     presentation-only changes, behavior-preserving refactors, bug fixes, and public contract changes.
  3. Implement the complete improvement, including in-scope consumers, module-owned tests, and
     documentation. Search the repository for stale names, duplicated alternatives, and obsolete
     usage patterns. Keep unrelated cleanup in separate, reviewable batches.
  4. Format selected files with the checkout-local compiler, inspect every resulting change, and
     confirm a second pass is stable. Review correctness, idiomatic language use, ownership, API
     consistency, teaching value, and reading effort. Re-read formatted functions beyond the diff.
     Remove cosmetic churn, accidental generated changes, and line-ending noise. Preserve fixture
     intent; fix or report an unresolved formatter conflict rather than accepting a harmful rewrite.
  5. Run the validation selected by validate-swag-changes: the owning module's focused tests,
     compiler regression boundary or an affected module-owned test. A shipped application may be
     built only when needed to verify a standard-module compatibility contract; do not inspect or
     change its implementation as campaign work.
     Do not rebuild the compiler for comments and whitespace alone. Exercise source-sensitive
     inputs when affected and inspect documentation output when comments can reach it. Add
     configurations, compiler builds, and broader coverage only when the changed behavior requires
     them. Inspect affected goldens; never weaken tests or promote differences merely to pass.
  6. Update semantic and visual coverage and validation evidence, commit the retained batch, and
     integrate it under the shared protocol. Continue through every remaining area. A green build,
     one cleaned module, or a large diff does not mean the whole tree has been reviewed.

IMPROVE THE PLATFORM WHEN IT GETS IN THE WAY

When idiomatic Swag is awkward because of a library defect, compiler defect, or missing language
capability, investigate the cause. Fix discovered defects with focused regression coverage under
the shared protocol; do not spread local workarounds across bin/. Surface syntax changes require
reference and editor updates. If a missing capability requires a design decision, keep that
separate from a concrete defect and do not claim the affected area is complete until the decision
and implementation are resolved.

THE CAMPAIGN MAY END ONLY WHEN

  - Every project-owned Swag source and public API family in `bin/runtime/`, its runtime-owned
    tests and helpers, and the recorded app-used standard-module dependency closure has received
    semantic and visual review, with explicit per-file coverage and justified exclusions for
    generated or upstream material and intentional fixtures. No in-scope directory is silently
    omitted.
  - Every actionable improvement found in scope is implemented and validated; every remaining
    design or external blocker is identified precisely and prevents a claim of full completion.
  - In-scope APIs, implementations, module-owned tests and documentation agree, with no stale
    names, partial migration, unexplained duplicate implementation, or obsolete recommended idiom.
  - A final reread finds no further justified visual improvement in the reviewed code. Formatting
    is stable, and presentation-only batches preserve logic and source-sensitive behavior.
  - Validation selected from the complete final diff is green, including affected consumers and
    inspected golden outputs. No disabled test, weakened assertion, or unreviewed golden hides a
    regression. Earlier evidence is rerun when a later change invalidates it.
  - Required generated documentation is current, and no temporary output, accidental upstream edit,
    or line-ending-only change remains in the final diff.

Do not stop after the easy style fixes or the first directory. Continue until the coverage table
accounts for all in-scope code in both dimensions. If completion is blocked, deliver the validated
improvements and state exactly what remains. If the user specifies a time limit, stop at that
limit and report reviewed and unreviewed areas; elapsed time does not establish whole-tree coverage.
Never claim that the in-scope runtime and standard modules are complete on the strength of a sample
or a formatter invocation.

REPORT

Report the worktree and branch, the app-used standard-module closure, reviewed areas, unchanged areas
and exclusions, meaningful before/after examples explaining both design and reading benefits,
refactorings and simplifications,
API contract changes and caller migrations, defects fixed, platform findings, documentation updates,
and every validation command and result. Include the final semantic and visual coverage table and
any remaining blockers or uncertain cases so the whole-tree review can be verified.
```
