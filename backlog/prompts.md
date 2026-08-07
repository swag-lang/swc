# Campaign Prompts

Five long-running campaigns, one prompt each, ready to copy into a fresh session. They are not
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

Campaigns 3, 4 and 5 constrain each other on purpose: shrinking the sources must not cost speed,
speed must not cost memory, and memory must not cost speed. Run them one at a time, and let each
one re-measure the other two's numbers before claiming a win.

Every one of them runs in its own worktree, never in the main checkout — each prompt says so, and
it is not a formality. A campaign spans many rounds, keeps binaries and measurements around, and
reverts whole rounds; a shared tree picks up foreign uncommitted edits from other sessions, and
MSBuild's incremental build then links someone else's in-flight code into the binary being
measured. The failures that produces look exactly like the bug the campaign was chasing.

---

## 1. Generated-code performance

```
You are running a long optimization campaign on the swc backend. Read AGENTS.md and the skills it
points to first, then backlog/todo.compiler.md, backlog/findings.optimization.md, and bench/README.md.

WORK IN A SEPARATE WORKTREE

Do not run this campaign in the main checkout. Create an isolated worktree and do everything there:

  git worktree add --detach ../swc-perf HEAD

This is not hygiene, it is measurement validity. A shared tree picks up foreign uncommitted edits
from other sessions, and MSBuild's incremental build then links that in-flight code into the
swc.exe you are timing - so a number moves and it is not yours. It also lets you abandon a whole
round with one checkout instead of unpicking it, which you will do often here.

Before the first change, build and run the full test sequence AT BASELINE in the new worktree, and
record a baseline bench campaign there. Any failure or number at that point is pre-existing, not
yours. Attributing a baseline failure to your own change costs a session every time it happens.

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

Re-measure before you act. That table is one campaign on one machine; if your first full campaign
disagrees with it, yours is the truth and the table is history.

THE LOOP

Pick the task with the worst ratio that you have not already exhausted, then:

  1. Read the assembly clang-cl produces for that task before you read ours. It is the answer
     sheet: it tells you what the win actually is, and it has repeatedly turned out to be
     something other than the transformation that looked obvious from our side (it does not
     vectorize the ChaCha rounds at all - it keeps sixteen words in sixteen registers).
  2. Dump our micro code for the same function and find the specific difference: instruction
     count, memory operations in the loop, spills, dependency chain length. Name the mechanism
     before you touch a pass.
  3. Implement the smallest change that addresses that mechanism, in src/Backend/Micro/Passes
     or the encoder.
  4. Measure the task alone while iterating: cd bench && py driver.py --tasks <task> --quick.
     Partial sweeps are never recorded; they are for your inner loop only.
  5. Validate correctness before believing any number: tools/tests.bat dm, then
     tools/tests.bat dm --all-cfg. A checksum mismatch in bench means you measured nothing.
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
  7. Record a full campaign only when you have a result worth keeping:
     tools\bench.bat --label "what changed". That takes ~25 minutes; do not spend one per experiment.

DO NOT STOP AT THE FIRST FAILURE

Most of these experiments will fail. That is the normal shape of this work, and three of the
entries already in backlog/findings.optimization.md are failed attempts written down so the next
one does not repeat them. When something does not work:

  - Revert it cleanly.
  - Write down what it ruled out, with the measurement, as an F-NNN entry in
    backlog/findings.optimization.md (take the identifier from backlog/README.md and advance it).
  - Take the next hypothesis from the same mechanism, or move to the next task.

The campaign ends when the goal above is met, or when you have run out of hypotheses on every task
- meaning three consecutive rounds across the whole task set left the emitted code no closer to
what clang-cl and MSVC emit. It does not end because one pass turned out to miscompile, one idea
lost 2%, or one task resisted.

RULES

  - Correctness first, always. tools/tests.bat dm and --all-cfg must be green before any number is
    believed, and the Release sequence before anything is recorded. A pass that miscompiles under
    the JIT but passes unit tests is the known failure mode here - tools/scripts.bat dm is what
    catches it (see F-036).
  - Generated-code quality outranks compile time in this campaign. A backend optimization that
    works is never reverted because it costs compile time: generating better code legitimately
    takes longer, and campaign 4 is where compile time is bought back. Measure the cost, say it
    explicitly, and then make the implementation cheaper - a slow analysis is a slow analysis, not
    a reason to give up the optimization. Only a change that is BOTH slower to compile AND not
    better in the generated code gets reverted.
  - Never change what a bench task computes. That silently resets the history.
  - A/B two swc.exe binaries by CPU time, alternating order, sampling before the process exits.
  - Findings you cannot chase now go in backlog/findings.optimization.md with evidence and a next
    step. Entries that graduate into a plan move to backlog/todo.compiler.md.

REPORT

After each round, one table: what you tried, what it measured, kept or reverted, and why. At the
end of the campaign, the new ratio table next to the one above.
```

---

## 2. Safety without annotations

```
You are running a long campaign on Swag's safety guarantees. Read AGENTS.md and the skills it
points to first, then backlog/findings.safety.md, backlog/findings.compiler.md, and the language
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

What is left is precision, and every open item is written down as a finding: a view judged by
source order rather than by control flow (F-041), views into a global owner's payload never judged
(F-042), and a backend check the language rule has made unreachable from source (F-043).

THE LOOP

For each check, in this order, and do not skip step 1:

  1. Write the tests first, both halves. The positives that MUST fire, in bin/unittests/sanity,
     and - this is the half that decides whether the check is usable - the negatives that must
     stay SILENT: an interface or pointer to the value itself, a method that only reads or assigns
     fields, a view rebound after the container grew, a container of views whose owner outlives
     them. A check with no negative tests is a check that will be turned off.
  2. Implement the smallest analysis that passes both halves.
  3. Sweep the whole tree for false positives, and mean the whole tree: tools/build.bat,
     tools/std.bat, tools/apps.bat, tools/examples.bat, tools/reference.bat. The baseline is zero
     hits. Every workspace being clean today proves nothing, because nothing fires - the sweep only
     becomes evidence once the check works.
     A 'build' sweep is HALF a sweep: it never compiles the '#test' bodies, and a quarter of the
     standard library's interesting code lives there (Array's self-append test is where the first
     false positive of the invalidation check turned up, long after build.bat came back clean).
     Sweep with 'test' as well, or just run tools/tests.bat dm and read its first failure.
  4. Triage every hit, one at a time, into exactly one of two buckets: a real defect in bin/ (fix
     it, it is a genuine find) or a false positive (fix the analysis). There is no third bucket.
  5. Never silence a false positive by narrowing the check until it stops firing. That is how a
     check ends up complete and useless, firing on nothing. If a shape genuinely cannot be judged,
     say so as a finding and leave the check firing on what it can prove.
  6. tools/tests.bat dm, then --all-cfg, then the Release sequence.

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
    fast-debug and invisible in release. Ask what actually happened - an expanded call no longer
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
then backlog/findings.tooling.md (F-037) and backlog/todo.compiler.md entry 3.

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

  221 172 lines across 611 files, excluding vendored mimalloc and the C++ unit tests.
  Compiler 124 900 · Backend 52 893 · Support 25 824 · Main 13 147 · Format 8 442 · Doc 4 585.
  The largest single files: Pass.RegisterAllocation.cpp 3748, X64Encoder.cpp 3702,
  SemaEscape.cpp 3542, Match.Func.cpp 3074, SemaInline.cpp 2589, CompilerInstance.Module.cpp 2562,
  SemaClone.cpp 2520.

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
  - Templating families of near-identical functions to make them look shorter. F-037 measured
    this: every instantiation gets its own body, /OPT:ICF only folds the ones that come out
    identical, and the interesting ones - differing by a constant - never do. Round two of that
    sweep removed 210 lines and GREW the executable by 3 072 bytes.
  - Sharing a small helper that was being inlined. The same measurement found 1 536 bytes came
    back purely from having to put two helpers back inline in their headers.

THE PROOF, EVERY ROUND

A round is not done until all four hold:

  1. tools/tests.bat dm, then tools/tests.bat dm --all-cfg, then Release build, then
     tools/tests.bat. All green.
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

Sema is 124 900 lines with essentially one C++ unit test, which is exactly why it feels dangerous
to touch and exactly why it is where the mass is. Do not refactor sema blind: when a decision
procedure is table-shaped and pure - overload ranking in Match.Func.cpp, cast legality, generic
deduction in SemaGeneric.Deduce.cpp - write the table-driven C++ test FIRST in src/Unittest, then
cut. That test is worth more than the lines it lets you remove, and it is entry 3 of
backlog/todo.compiler.md.

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
then backlog/todo.compiler.md entries 1, 2, 4, 6 and 7.

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
  - tools/web.bat (the whole documentation site) and tools/format.bat (every Swag workspace):
    unmeasured today. Measure them, then halve them.

For context on where the bar already is, from campaign 20260806-174758: swc builds the bench tasks
in 93-132 ms against clang-cl's 481-647 ms and rustc's 425-585 ms. This campaign is not about
beating them. It is about the loop a person actually sits in.

START BY BUILDING THE INSTRUMENT

Do this before any optimization; nothing below can be judged without it, and it is entry 4 of
backlog/todo.compiler.md.

Today the only compiler-side numbers recorded anywhere are hello_build_ms and hello_build_peak_mb
in bench/history.json - one four-line program. Across eleven campaigns it reads 92, 61, 74, 68, 74,
64, 66, 85, 81, 95, 67 ms: noise around a flat line, on a workload too small to contain what costs.

Add real workloads to the campaign: a full core rebuild, a warm no-op, a one-file-touched rebuild,
a full doc generation, a full format pass. Wall time and peak working set for each, recorded in
history.json the same way and normalized the same way.

Then decide whether the per-stage counters should exist in the Release binary behind a flag. They
exist today - lexer, parser, sema, codegen and Micro timings, plus AST, type, symbol and
instruction counts in src/Main/Stats.h - but they are behind SWC_HAS_STATS, which only the separate
Stats build configuration defines. In the shipped binary --stats prints four lines. A profile
nobody can take on the shipping build is a profile nobody takes.

THE LOOP

  1. Profile the target workload. Name the stage that costs, with a number.
  2. Form one hypothesis about why, and predict what the fix should buy before you write it.
  3. Implement the smallest version of it.
  4. Measure against the prediction. A fix that lands far off its prediction means the model was
     wrong - go back to step 1 rather than keeping an accidental win.
  5. tools/tests.bat dm, --all-cfg, Release sequence.
  6. Record it in the campaign.

THE FOUR STRUCTURAL LEVERS, IN ORDER

They are not independent, and taking them out of order wastes the work:

  1. The module boundary is re-parsed Swag source. core publishes 16 files and 12 328 lines per
     configuration, and every dependent module lexes, parses and re-analyzes all of it. A binary
     module interface, loaded lazily by name, is entry 1 and it unlocks 2, 6 and 8.
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
record the measurement in backlog/findings.tooling.md, and take the next piece - the four levers
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
backlog/todo.compiler.md entry 5.

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

  - core rebuild under 250 MB fast-debug.
  - Hello world under 50 MB.
  - Bench task builds at or below clang-cl's 69 MB.
  - Compile time unchanged, measured, not assumed.

START BY MAKING THE NUMBER ATTRIBUTABLE

There is no per-subsystem memory accounting today - only an OS peak. The split between AST, types,
symbols, constants and Micro is currently UNKNOWN, which means every optimization before this step
is a guess. MemoryProfile exists but sits behind the same SWC_HAS_STATS gate as everything else in
src/Main/Stats.h.

Build the accounting first: bytes live per subsystem, sampled at peak, available in a build a
person can actually run. Then attack what it shows, not what it seemed like.

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
  5. tools/tests.bat dm, --all-cfg, Release sequence.
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
