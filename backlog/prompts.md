# Campaign Prompts

Seven long-running campaigns, one prompt each, ready to copy into a fresh session. They are not
tasks: each one is a target that takes many rounds to reach, and each prompt is written to keep an
agent working through the rounds instead of stopping at the first thing that does not work.

Each prompt is self-contained. It names the goal, the numbers as they stand today, the loop to run,
the rules that must not be broken, and — most importantly — the condition under which the campaign
is allowed to end. Every number quoted below was measured on this tree and is reproducible with the
command next to it; an agent that acts on a stale number is guessing, so every prompt starts by
re-measuring.

| Campaign | Target |
| --- | --- |
| [1. Generated-code performance](#1-generated-code-performance) | Reach clang-cl and MSVC on `bench/` |
| [2. Safety without annotations](#2-safety-without-annotations) | Rust-class guarantees with nothing for the user to write |
| [3. Compiler code mass](#3-compiler-code-mass) | A much smaller `swc`, byte-for-byte as capable |
| [4. Compilation speed](#4-compilation-speed) | The fastest thing that does this work |
| [5. Compiler memory](#5-compiler-memory) | A fraction of the resident set, at the same speed |
| [6. Repository health reset](#6-repository-health-reset) | Restore a clean, current, all-green baseline |
| [7. Compiler code cleanup](#7-compiler-code-cleanup) | Eliminate every actionable Rider clang-tidy diagnostic |

Campaigns 3, 4 and 5 constrain each other on purpose: shrinking the sources must not cost speed,
speed must not cost memory, and memory must not cost speed. Run them one at a time, and let each
one re-measure the other two's numbers before claiming a win.

Campaigns 1 through 5 and campaign 7 run in their own worktree, never in the main checkout.
Campaign 6 runs directly on `master`; each prompt states its own rule. For the isolated campaigns,
the worktree is not a formality. A campaign spans many rounds, keeps binaries and measurements
around, and reverts whole rounds; a shared tree picks up foreign uncommitted edits from other
sessions, and
MSBuild's incremental build then links someone else's in-flight code into the binary being
measured. The failures that produces look exactly like the bug the campaign was chasing.

---

## 1. Generated-code performance

```
You are running a long optimization campaign on the swc backend. Read AGENTS.md and the skills it
points to first, then backlog/compiler.md, backlog/optimization.md, and bench/README.md.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-perf HEAD

This is not hygiene, it is measurement validity. A shared tree picks up foreign uncommitted edits
from other sessions, and MSBuild's incremental build then links that in-flight code into the
swc.exe you are timing - so a number moves and it is not yours. It also lets you abandon a whole
round with one checkout instead of unpicking it, which you will do often here.

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
     or the encoder.
  4. Re-dump and re-count the same loops. This is the inner loop of the campaign and it costs
     seconds - one build, one count. Iterate here, not on the clock. Compare per loop and never on
     a total: an outer loop's span contains its inner loops, so a saving inside one shows up as a
     loss outside it.
  5. Validate correctness once the counts say the change is real, not before. swc tools/tests.swgs
     dm, then swc tools/tests.swgs dm --all-cfg. Running these before there is a change to validate
     is the most reliable way this campaign wastes a session. A checksum mismatch in bench means
     you measured nothing.
  6. Judge the change against clang-cl and MSVC's output, not against the clock. The clock on this
     machine drifts more than most single changes are worth (two campaigns of the SAME binary
     measured a geometric mean of 1.41x and 1.54x, and drift inside one sweep reached +37%), and
     the context factor does not remove it. So: a change that provably moves the emitted code
     toward what the best compilers emit is kept even when the measurement is flat or slightly
     negative. They are right; matching them comes first, and beating them comes later.
     What "provably" means here is the per-loop count, which is deterministic: instructions and
     memory operations per iteration of each hot loop, before and after, next to the same loop in
     clang's assembly. A change is only reverted when the emitted code is not better - not when the
     benchmark fails to see that it is.
     One consequence worth planning around: a change can be a necessary step whose own measurement
     is flat, or even briefly negative, because it enables the next one. Say so, keep it, and name
     the follow-up.
  7. Reach for the clock only once the emitted code says the change is real and you want its size:
     cd bench && py driver.py --tasks <task> --quick. Partial sweeps are never recorded; they are
     for your inner loop only.
  8. Record a full campaign only when you have a result worth keeping:
     swc tools\bench.swgs --label "what changed". That takes ~25 minutes; do not spend one per
     experiment, and record the baseline it is compared against in the same session - a baseline
     measured hours earlier is a different machine.

DO NOT STOP AT THE FIRST FAILURE

Most of these experiments will fail. That is the normal shape of this work, and three of the
entries already in backlog/optimization.md are failed attempts written down so the next
one does not repeat them. When something does not work:

  - Revert it cleanly.
  - Write down what it ruled out, with the measurement, as a B-NNN entry in
    backlog/optimization.md (take the identifier from backlog/README.md and advance it).
  - Take the next hypothesis from the same mechanism, or move to the next task.

The campaign ends when the goal above is met, or when you have run out of hypotheses on every task
- meaning three consecutive rounds across the whole task set left the emitted code no closer to
what clang-cl and MSVC emit. It does not end because one pass turned out to miscompile, one idea
lost 2%, or one task resisted.

RULES

  - Correctness first, always. swc tools/tests.swgs dm and --all-cfg must be green before any number is
    believed, and the Release sequence before anything is recorded. A pass that miscompiles under
    the JIT but passes unit tests is the known failure mode here - swc tools/scripts.swgs dm is what
    catches it (see F-036).
  - Generated-code quality outranks compile time in this campaign. A backend optimization that
    works is never reverted because it costs compile time: generating better code legitimately
    takes longer, and campaign 4 is where compile time is bought back. Measure the cost, say it
    explicitly, and then make the implementation cheaper - a slow analysis is a slow analysis, not
    a reason to give up the optimization. Only a change that is BOTH slower to compile AND not
    better in the generated code gets reverted.
  - Never change what a bench task computes. That silently resets the history.
  - A/B two swc.exe binaries by CPU time, alternating order, sampling before the process exits.
  - Leads you cannot chase now go in backlog/optimization.md with evidence and a concrete `Next:`
    step. If the evidence establishes implementation work, update that entry in place.

REPORT

After each round, one table: what you tried, what it measured, kept or reverted, and why. At the
end of the campaign, the new ratio table next to the one above.
```

---

## 2. Safety without annotations

```
You are running a long campaign on Swag's safety guarantees. Read AGENTS.md and the skills it
points to first, then backlog/safety.md, backlog/compiler.md, and the language
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

What is left is precision, and the live entries in `backlog/safety.md` are the authority.
They currently include parameter-owned views (F-088), macro and inline expansions judged against
the wrong body (F-089), and a backend check the language rule has made unreachable from source
(F-043). Re-read that file before choosing a round;
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

## 3. Compiler code mass

```
You are running a code-quality campaign on the swc C++ sources. Read AGENTS.md and the skills it
points to first - especially .agents/skills/modify-swag-codebase/references/cpp-coding-rules.md -
then the focused Sema tests in src/Unittest/Sema/Test.Sema.DecisionProcedures.cpp.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-shrink HEAD

This campaign reverts rounds by design - the four-part proof below is built to reject them - and a
reverted round has to be reverted CLEANLY, across dozens of files, with nothing of it left behind.
That is one checkout in an isolated tree and an archaeology session in a shared one. It also keeps
foreign uncommitted edits out of the binary whose size and timing you are comparing, which is the
whole basis of the proof.

Before the first change, build and run the full test sequence AT BASELINE in the new worktree, and
record the baseline swc.exe size, compile-time median and peak memory there. Every later round is
compared against those three numbers, not against numbers from another tree.

GOAL

Make swc dramatically smaller in source without giving up one instruction of capability, one
millisecond of compile time, or one megabyte of compiler memory. The sentence this campaign is
trying to earn is: "swc is tiny, and it does all of that."

Where it stands, reproducible from src/:

  find . \( -name "*.cpp" -o -name "*.h" -o -name "*.inc" \) \
       -not -path "./Support/Memory/mimalloc/*" -not -path "./Unittest/*" -exec cat {} + | wc -l

  As of 2026-08-09: 224 337 lines across 615 files, excluding vendored mimalloc and the C++ unit
  tests. Compiler 125 908 · Backend 54 082 · Support 17 018 · Main 13 430 · Format 8 442 ·
  Doc 5 261. Recompute this baseline before starting a campaign.
  The largest single files: SemaEscape.cpp 3989, Pass.RegisterAllocation.cpp 3748,
  X64Encoder.cpp 3702, Match.Func.cpp 3032, CompilerInstance.Module.cpp 2801,
  SemaInline.cpp 2591, SemaClone.cpp 2520.

THE ONLY KIND OF CHANGE ALLOWED

One-for-one, no possible side effect. Every edit must be provably behavior-preserving by
inspection alone:

  - Delete dead code, unreachable branches, unused helpers, and unused parameters.
  - Collapse verbatim or near-verbatim duplicates into one shared function.
  - Replace hand-written switch/if ladders with the table they already are.
  - Remove a layer that only forwards.
  - Simplify control flow whose shape is the same on every path.

Explicitly NOT allowed, however tempting:

  - Any change to what the compiler accepts, rejects, emits, or reports.
  - "While I am here" bug fixes. Those are separate commits, or findings.
  - Templating families of near-identical functions to make them look shorter. Measured on this
    repository: every instantiation gets its own body, /OPT:ICF only folds the ones that come out
    identical, and the interesting ones - differing by a constant - never do. Round two of that
    sweep removed 210 lines and GREW the executable by 3 072 bytes.
  - Sharing a small helper that was being inlined. The same measurement found 1 536 bytes came
    back purely from having to put two helpers back inline in their headers.

Source deletion is nearly free in the image, which is why the size proof below is a tolerance and
not a target: /OPT:ICF on top of LTCG already folds byte-identical bodies, so a full round of
1 398 removed lines moved bin/swc.exe by only 10 240 bytes, 0.2%. Should the image itself ever
become the goal, measure where it actually goes first - dump the section sizes and the largest
COMDATs (link /dump /headers, a /MAP file) and separate code from the read-only data the
diagnostic, token and instruction tables contribute. Only two levers are likely to matter, and
both must be weighed against the rule that the compiler may never get slower: cutting template
instantiation in the hot headers, and trimming inlining pressure (/Ob1 on the cold
command/report/doc translation units only, never on sema, codegen, or the micro passes).

THE PROOF, EVERY ROUND

A round is not done until all four hold:

  1. swc tools/tests.swgs dm, then swc tools/tests.swgs dm --all-cfg, then Release build, then
     swc tools/tests.swgs. All green.
  2. bin/swc.exe size within +/-0.3% of where the round started.
  3. Compile time within noise: A/B the two swc.exe binaries on the same workload, CPU time,
     medians over at least eight order-alternated rounds, --num-cores 1.
  4. Peak compiler memory within noise on the same workload.

If any of the four moves, the round is reverted, not explained.

THE LOOP

  1. Pick one subsystem. Start where the mass is and where the tests are strongest - Backend/Micro
     and Format both have real C++ suites and are the safest ground.
  2. Read for duplication and for layers, not for style. Grep for repeated bodies.
  3. Cut. Aim for at least 500 net lines removed in the round.
  4. Run the four-part proof.
  5. Commit the round on its own so it can be reverted alone.

Sema is 81 570 physical lines across 150 files and has two focused C++ test units totaling only
374 physical lines. It remains dangerous to refactor blind. The table-driven tests for overload
ranking, cast legality, and generic deduction live in
src/Unittest/Sema/Test.Sema.DecisionProcedures.cpp; extend them before changing those decision
procedures, and add an equally focused seam before refactoring another semantic subsystem.

DO NOT STOP AT THE FIRST FAILURE

A reverted round is normal - it means the four-part proof did its job. Note what moved and why,
pick a different subsystem, and continue. A subsystem that resists three rounds is a subsystem to
leave alone and record as such.

The campaign ends when three consecutive rounds fail to find 500 removable lines anywhere in the
tree. It does not end because one refactor grew the binary or one suite went red.

REPORT

Per round: subsystem, lines before and after, exe size delta, compile-time A/B medians, memory
delta. Cumulative total at the top, so the number is one line at any moment.
```

---

## 4. Compilation speed

```
You are running a compile-speed campaign on swc. Read AGENTS.md and the skills it points to first,
then backlog/compiler.md T-001, T-002, T-004, T-006 and T-007.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-speed HEAD

Every claim in this campaign is a timing, and a timing taken in a shared tree is worthless: foreign
uncommitted edits from other sessions get linked into your swc.exe by MSBuild's incremental build,
and a second build running on the same machine moves the number by more than anything you will
change. The levers below are also large, staged rewrites - a module interface format, a caching
layer - which need somewhere they can be half-finished without blocking anyone.

Before the first change, build and run the full test sequence AT BASELINE in the new worktree, and
record every workload's time there once the instrument below exists. Those are the numbers every
later round is measured against.

GOAL

Make swc the fastest thing that does this work - not just faster than C++ and Rust toolchains,
which it already is, but fast enough that the edit-build loop stops being a loop. All three
commands count: build, doc, format.

Targets, all on this machine, all re-measured before you start:

  - std/core rebuild (291 files, 50 690 lines): 2.1 s today, fast-debug. Target under 1.0 s.
  - Warm no-op build of the same: target under 100 ms.
  - Edit one file in core, rebuild: today this rebuilds all 291 files. Target under 300 ms.
  - Hello world, source to linked executable: 89 ms today. Target under 50 ms.
  - swc tools/web.swgs (the whole documentation site) and swc tools/format.swgs (every Swag workspace):
    unmeasured today. Measure them, then halve them.

For context on where the bar already is, from campaign 20260806-174758: swc builds the bench tasks
in 93-132 ms against clang-cl's 481-647 ms and rustc's 425-585 ms. This campaign is not about
beating them. It is about the loop a person actually sits in.

START BY BUILDING THE INSTRUMENT

Do this before any optimization; nothing below can be judged without it, and it is T-004 in
backlog/compiler.md.

Today the only compiler-side numbers recorded anywhere are hello_build_ms and hello_build_peak_mb
in bench/history.json - one four-line program. Across eleven campaigns it reads 92, 61, 74, 68, 74,
64, 66, 85, 81, 95, 67 ms: noise around a flat line, on a workload too small to contain what costs.

Add real workloads to the campaign: a full core rebuild, a warm no-op, a one-file-touched rebuild,
a full doc generation, a full format pass. Wall time and peak working set for each, recorded in
history.json the same way and normalized the same way.

Use external profilers for per-stage investigation. Do not add optional counters, allocation
tracking, or profiling-only branches to the compiler: the benchmark campaign owns stable wall-time
and peak-working-set measurements, while focused external traces answer transient questions.

THE LOOP

  1. Profile the target workload. Name the stage that costs, with a number.
  2. Form one hypothesis about why, and predict what the fix should buy before you write it.
  3. Implement the smallest version of it.
  4. Measure against the prediction. A fix that lands far off its prediction means the model was
     wrong - go back to step 1 rather than keeping an accidental win.
  5. swc tools/tests.swgs dm, --all-cfg, Release sequence.
  6. Record it in the campaign.

THE FOUR STRUCTURAL LEVERS, IN ORDER

They are not independent, and taking them out of order wastes the work:

  1. The module boundary is re-parsed Swag source. core publishes 16 files and 12 328 lines per
     configuration, and every dependent module lexes, parses and re-analyzes all of it. A binary
     module interface, loaded lazily by name, is T-001 and it unlocks T-002, T-006 and T-008.
  2. Incrementality stops at the module. Editing one line rebuilds 291 files. Per-file frontend
     caching first, then per-function codegen caching - the second is where the win is and it is
     unreachable without lever 1.
  3. Every invocation re-analyzes the prelude: 8 files, 19 494 tokens, 237 functions before a
     single line of user code. That is 62% of hello world. This is lever 1 applied to the prelude
     - do it AFTER lever 1, or the compiler ends up with two module-loading mechanisms.
  4. Modules build one at a time. The job system parallelizes hard WITHIN a module and the
     workspace scheduler runs modules serially, on a 22-worker machine. The compile-speed branch
     already prototypes the DAG scheduler. Finish it against the memory number, because N
     concurrent modules multiply peak memory by N - coordinate with campaign 5.

Doc and format have had no attention at all and are probably cheaper wins than any of the four.
Measure them before assuming otherwise.

DO NOT STOP AT THE FIRST FAILURE

These are large changes and the first attempt at a binary module interface will not be the one
that ships. Land it in pieces that each keep the tree green. When a piece does not pay, revert it,
record the measurement in backlog/tooling.md, and take the next piece - the four levers
above are months of work and the campaign is designed to survive individual failures.

The campaign ends when the five targets are met. It does not end because one lever turned out to
be harder than it looked.

RULES

  - Never trade correctness for speed. The full sequence is green or the change does not exist.
  - Never trade generated-code quality for compile speed without measuring both. Run bench.
  - Never trade memory for speed without measuring both - campaign 5 owns that number and a
    regression there is a regression here.
  - A measurement taken once is a guess. Medians over order-alternated runs, or it is not a number.

REPORT

The five targets as a table, current versus target, refreshed every round. Under it, what changed
and what it bought.
```

---

## 5. Compiler memory

```
You are running a memory campaign on swc. Read AGENTS.md and the skills it points to first, then
backlog/compiler.md T-005.

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

Where it stands:

  - std/core rebuild (50 690 lines): 671.9 MB peak working set in fast-debug, ~490 MB in release.
    That is roughly 13 KB of resident memory per source line.
  - Hello world: 81.6 MB peak. To print one line.
  - From campaign 20260806-174758, building the bench tasks: swc peaks at 106-118 MB where
    clang-cl peaks at 69 MB and MSVC at 82-101 MB. rustc peaks at 201 MB. On these tiny programs
    swc is the second-worst of the four.

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

## 6. Repository health reset

```
You are running a repository-wide health reset on swc. Read AGENTS.md and every skill it points to
before acting, then README.md, tools/README.md, backlog/README.md, and every domain file listed in
the backlog inventory. Read the additional area-specific skills as soon as a discovered fix enters
their scope.

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
runs launched by AI agents, including Codex and Claude, are exclusive with one another across all
worktrees. Follow the agent-to-agent serialization rules in modify-swag-codebase before every build
and every test campaign. IDE builds and manually launched user commands do not occupy the agent
slot; never terminate or interfere with them.

Record the starting commit, `git status --short --branch`, toolchain versions, and the available
external prerequisites before changing anything. A starting failure is useful attribution, but it
is not an exemption: this campaign fixes baseline failures too.

GOAL

Leave one reproducible baseline from which new work can start without inheriting noise or doubt:

  - DevMode and Release compilers build from source.
  - Every canonical build, test, integration, smoke, and packaging campaign listed below is green.
  - Every project-owned Swag and C++ source is canonically formatted, and a second formatting pass
    changes nothing.
  - Generated documentation and website assets are current, reviewed, and reproducible; a second
    generation changes nothing.
  - Every backlog entry is truthful, current, unique, correctly numbered, correctly linked, and
    stored in the right domain. Resolved or invalid entries are gone.
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

AUDIT THE REPOSITORY BEFORE TRUSTING THE TESTS

Build an inventory before the first fix:

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
     acceptance conditions, and next actions, merge duplicates, and re-evaluate semantic priority.
     When investigation establishes implementation work, update the same entry in place and retain
     its identifier. Audit files with no recent commit too, and delete empty category files rather
     than treating their existence as coverage.
  4. Check backlog invariants mechanically: unique permanent identifiers, the `Next identifier`
     counter above every allocated `B-*` identifier, valid Markdown anchors and file links, no
     dangling live cross-reference, and no undocumented backlog file. A `Related:` line names live
     entries only; a retired identifier may remain solely as explicit historical provenance.
     Position expresses expected value and must be judged semantically, not sorted by identifier.
  5. Check repository instructions, READMEs, public API documentation, the language reference,
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

After the first DevMode compiler build:

  1. Format every Swag workspace with `bin\swc.exe tools\format.swgs dm`.
  2. Format every project-owned compiler `.cpp`, `.h`, and `.inc` file under `src/` with
     clang-format and the repository `.clang-format`. Exclude vendored mimalloc sources; do not
     rewrite third-party code.
  3. Run both formatters a second time and prove that the second pass introduces no additional
     change. Review the complete formatting diff; formatting is not permission to hide a semantic
     change or rewrite unrelated generated/vendor files.
  4. Regenerate the complete documentation site and brand assets with
     `bin\swc.exe tools\web.swgs dm`. Review every tracked change for correctness, including public
     API pages, the executable language reference, links, images, indexes, and examples.
  5. Run the documentation generation a second time and prove it is idempotent. Fix the generator
     if it is not; do not normalize nondeterministic output as expected churn.

When formatting or documentation exposes a compiler or tool defect, fix that defect at the root
and add its regression test. Never hand-edit generated output to make the diff look right.

RUN THE COMPLETE VALIDATION LADDER

Run these in order, stopping at the first failure as the tooling requires. After any fix, rerun the
smallest focused reproducer first, then restart every affected aggregate campaign. Once the tree
appears clean, run this entire ladder again from the beginning on the final sources:

  1. Build `swc.dm.exe` with the DevMode solution configuration.
  2. `bin\swc.exe tools\build.swgs dm --all-cfg` - build every workspace in release and devmode,
     including modules that have no tests.
  3. `bin\swc.exe tools\tests.swgs dm` - the full DevMode default campaign.
  4. `bin\swc.exe tools\tests.swgs dm --all-cfg` - the same five-rung campaign in both target
     configurations.
  5. Run `bin\swc.exe tools\vaultdrive.swgs dm` with the required WinFsp installation and privileges;
     this integration is intentionally outside tests.swgs and is part of a genuinely full pass.
  6. Build `swc.exe` with the Release solution configuration.
  7. `bin\swc.exe tools\tests.swgs` - the full Release validation campaign. Do not add a Release
     `--all-cfg` pass; the repository workflow deliberately reserves all-config coverage for
     DevMode.
  8. `bin\swc.exe tools\bench.swgs --quick` - prove the benchmark harness, generated programs, and
     cross-compiler comparison still work. Run a recorded full benchmark campaign if a fix touches
     generated-code performance or the measurement machinery.
  9. `bin\swc.exe tools\vsix.swgs` - refresh and package the VSCode extension with its documented
     Node.js/vsce prerequisites, then inspect the package result.

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

CLEAN THE TREE LAST

After the final validation, classify and remove temporary material created before or during the
campaign. Inspect `git status --short --ignored`, the preview from `git clean -ndX`, snapshot
actuals, crash files, scratch worktrees/files, and every `.output` directory under test sources.
Preserve `bin/unittests/.output` and `bin/unittests/workspace/.output`: they are canonical roots
owned by the test tooling. Remove another nested `.output` only after proving it is misplaced
generated output rather than an intentional fixture.

Remove only exact, reviewed targets. Do not use a broad destructive command against the repository,
the workspace root, or a computed path that has not been resolved and checked. Recheck for files
whose only difference is line endings, restore that noise in one batch, and retain every real
content change. Keep every final campaign commit directly on `master` so the repaired baseline is
immediately reachable from the branch it resets.

THE CAMPAIGN MAY END ONLY WHEN

  - The complete final validation ladder has passed after the last source, test, formatting, or
    documentation change.
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

## 7. Compiler code cleanup

```
You are running an exhaustive C++ code-cleanup campaign on the swc compiler. Read AGENTS.md and
the skills it points to first, especially modify-swag-codebase and its
references/cpp-coding-rules.md. This is an implementation campaign, not an audit: every actionable
problem the configured Rider clang-tidy pass reports in project-owned compiler code must be fixed,
validated, and removed from the next report.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Record the starting commit and status, then create
an isolated branch and worktree from that exact commit:

  git worktree add -b codex/compiler-cleanup ../swc-compiler-cleanup HEAD

Never copy uncommitted changes from the main checkout into it. The worktree keeps the large
inspection cache, generated reports, compiler binaries, and mechanical cleanup edits isolated from
unrelated work. Keep reports and downloaded command-line tools under the ignored .tmp directory.

RUN THE SAME PASS AS RIDER

Do not guess a convenient clang-tidy preset. Reproduce the effective configuration used by Rider's
Inspect Code action:

  1. Identify the installed Rider version and its bundled clang-tidy version.
  2. Read the solution, personal, and Rider global DotSettings layers. Record the configured
     CppClangTidy Checks value, inspection severity overrides, excluded paths, and any explicit
     clang-tidy configuration file.
  3. Use the matching JetBrains.ReSharper.GlobalTools version and run InspectCode on swc.sln with
     --no-build, --severity=HINT, the effective settings, absolute paths, and a SARIF output under
     .tmp. Use a bounded job count so the machine remains responsive.
  4. Confirm from the process list or debug log that InspectCode actually launches clang-tidy and
     loads the C++ project. A zero-result report produced without clang-tidy workers is not a clean
     baseline.
  5. Restrict conclusions to project-owned compiler sources under src/. Exclude vendored mimalloc
     code and generated output. Do not edit third-party sources to make the report green.

If InspectCode is unavailable, reconstruct its clang-tidy command from Rider logs and settings,
including checks disabled by inspection severity. Running a bare clang-tidy -checks=* is not
equivalent when Rider has appended disabled checks or supplied a different compilation database.

BASELINE

Parse the SARIF before editing. Produce a table grouped by rule with the count, affected files,
severity, and whether fixes are offered. Separate CppClangTidy diagnostics from native ReSharper
C++ inspections: the clang-tidy set is the required gate; native inspections are fixed when they
identify a real defect or a clear violation of the repository's C++ rules, but they must not
silently expand the campaign into cosmetic churn.

Inspect representative instances of every rule before applying any fix-it. Automatic fixes are a
starting point, not authority: several enabled checks can propose overlapping edits, and a fix
that shortens code can still violate the repository's performance, ownership, or readability
rules.

THE LOOP

Work one coherent rule family at a time:

  1. Read all occurrences and the surrounding implementation. Classify each diagnostic as a real
     defect, a safe maintainability improvement, or a demonstrated false positive.
  2. Fix the root cause. Preserve semantics, hot-path cost, allocation behavior, object layout,
     const correctness, and ownership. Share duplicated behavior at the owning abstraction; do not
     add file-local helpers before searching for an existing equivalent.
  3. Never silence a real issue with NOLINT, a ReSharper directive, a cast, an unused read, an
     empty branch, or a broader exclusion. A suppression is allowed only for a demonstrated tool
     false positive or a deliberate low-level construct, must target one rule at the narrowest
     location, and must explain the invariant that makes the code safe.
  4. Format only the touched C++ files with the repository clang-format configuration and inspect
     the diff. Reject unrelated formatting and line-ending churn.
  5. Rerun InspectCode on the affected files or project and prove that the targeted diagnostics
     disappeared without creating new ones. Keep a live before/after count by rule.
  6. When a diagnostic exposes a behavioral compiler defect, add the regression test at the real
     boundary before considering it fixed. A downstream discovery needs the required suite test in
     bin/unittests unless it genuinely cannot be reduced.

Prefer small reviewable rounds. Do not apply every available fix-it across src/ in one command:
bulk edits hide semantic changes, create conflicting rewrites, and make it impossible to attribute
a regression. Do not stop after fixing only warnings; HINT, SUGGESTION, WARNING, and ERROR severities
all belong to the configured pass and must be triaged.

VERSION AND VALIDATION

Any change under src/ requires one SWC_BUILD_NUM increment in src/Main/Version.h for the campaign,
not one increment per file. Before every compiler build or project test, follow the cross-agent
serialization rules in modify-swag-codebase; a separate worktree does not grant a separate build or
test slot.

After each risky rule family, run the narrowest focused C++ or Swag regression test. Once the final
inspection report is clean, run the complete C++ validation sequence required by the skill:

  1. Build DevMode.
  2. swc tools/tests.swgs dm
  3. swc tools/tests.swgs dm --all-cfg
  4. Build Release, including swc.exe.
  5. swc tools/tests.swgs
  6. swc tools/tests.swgs --all-cfg

Stop at the first test failure, release the shared test slot, fix the cause, rerun the focused
reproducer, and then restart the affected aggregate validation. If cleanup touches sema, codegen,
or a micro pass in a way that could affect performance, compare compile time and peak memory on the
same representative workspace before and after; code cleanup may not cost a compiler cycle or byte.
Treat every failure found by this ladder as part of the campaign, even when it predates or is
unrelated to a clang-tidy edit: reduce it, fix its root cause, and rerun the affected validation.

THE CAMPAIGN MAY END ONLY WHEN

  - A fresh full InspectCode report using the recorded Rider clang-tidy profile contains zero
    actionable diagnostics in project-owned src/ code.
  - Every remaining suppression or excluded diagnostic is individually justified as a false
    positive or intentional low-level construct; there are no blanket suppressions added by the
    campaign.
  - The DevMode and Release validation ladders, including every build configuration, are green
    after the last source edit.
  - SWC_BUILD_NUM is incremented exactly once, git diff --check is clean, and the final diff has no
    generated files, temporary reports, vendored edits, line-ending-only changes, or misplaced test
    output.

The campaign does not end because the report is smaller, because only hints remain, because an
automatic fix is unavailable, because a diagnostic predates the campaign, or because one check is
noisy. Demonstrate false positives precisely; fix everything else.

REPORT

Report the worktree path and branch, Rider/InspectCode/clang-tidy versions, effective checks and
exclusions, baseline and final counts by rule, files changed, suppressions retained or added with
their justification, SWC_BUILD_NUM change, and every validation command with its result.
```
