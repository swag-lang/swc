---
name: validate-swag-changes
description: Select, run, and report the smallest sufficient builds and tests for a Swag repository change. Use whenever planning validation, compiling swc or swc_devmode, choosing debug/fast-debug/release configurations, selecting compiler suites or bin module/application tests, focusing #test execution by source file, choosing concrete consumers, reviewing text or image goldens, or deciding whether a broad repository campaign is justified.
---

# Validate Swag Changes

Prove the behavior that moved with the cheapest boundary that can observe it. Do not infer a
campaign mechanically from changed paths and do not run every configuration by habit. Scheduled
full campaigns provide periodic breadth; change validation provides precise evidence.

Follow the build/test serialization rules in
[modify-swag-codebase](../modify-swag-codebase/SKILL.md) before taking either agent slot.

## Make Three Independent Decisions

Inspect the final diff and decide, in order:

1. Which compiler executable must drive validation: `swc_devmode.exe`, `swc.exe`, or both.
2. Which compiled-program configuration can execute the changed path: `debug`, `fast-debug`,
   `release`, or a justified union.
3. Which smallest behavioral boundary observes the change: one C++ test family, compiler source
   file, module test file, application consumer, smoke, generated diff, or golden.

Do not confuse the first two axes. `dm` chooses the DevMode compiler executable; `-bc release`
chooses the configuration of the Swag program that compiler builds.

Write the intended validation before launching it. Add a surface only when the changed behavior
can reach it.

## Choose The Compiler Executable

- Use the DevMode compiler by default. Its assertions, validators, statistics, and C++ unit tests
  give the strongest and fastest iteration signal.
- Build and use the Release compiler only when changing compiler architecture, scheduling,
  locking, job ownership, shutdown, process orchestration, or code guarded by
  `SWC_DEV_MODE`/a Release-only define; when reproducing a Release-compiler-only failure; or when
  measuring shipped compiler time, memory, or binary size.
- Treat a new possible deadlock, race, use-after-lifetime, or timing-dependent ordering as an
  architecture change. Exercise both compiler executables with real parallelism and repeat the
  focused reproducer when timing is part of the risk.
- Do not build the Release compiler merely because the program configuration is `release`.

## Choose Program Configurations

The registered presets are the contract:

| Configuration | Relevant properties | Select it for |
| --- | --- | --- |
| `debug` | no backend optimization; safety and sanity guards; full allocator diagnostics; no inlining | unoptimized lowering, debug allocator behavior, or debug-only execution |
| `fast-debug` | backend optimization; safety and sanity guards; debug information; marked-only inlining | the default path and optimized code that must retain guards |
| `release` | backend optimization; no runtime safety guards; sanity guards; automatic inlining, SSE2 vectorization, aggressive FP policy | Release-only optimization, inlining, vectorization, FP, or guard-free behavior |

Apply these reductions:

- Start with `fast-debug` when the code path exists in every preset.
- For an optimization or micro-pass change, omit `debug`: its backend pipeline is not optimized.
  Use `fast-debug` when it executes the pass. If the pass is self-gated by automatic inlining,
  vectorization, aggressive FP, or another Release-only decision, use `release` instead; add both
  configurations only when both execute distinct relevant paths.
- For runtime safety guards, use `debug` and/or `fast-debug` according to the reproducer and omit
  `release`, where those guards are disabled.
- For static sanity analysis, one representative configuration is enough unless the rule reads a
  configuration value or interacts with optimized lowering.
- For allocator capture/tracking/fill behavior, use `debug`. For the lighter guarded allocator
  path used during normal iteration, use `fast-debug`.
- Add a second configuration only for an actual semantic branch, preset difference, or known
  configuration-sensitive regression. `--all-cfg` is not a confidence shortcut.

## Choose The Smallest Boundary

### Non-executable changes

- Documentation-only compiler work (`src/Doc`, the `doc` command, or its private helpers): build
  DevMode, run `swc tools/web.swgs dm`, and inspect the generated HTML diff. Run no compiler or GUI
  campaign unless another command path changed.
- Formatter-only compiler work (`src/Format`, the `format` command, or its private helpers): build
  DevMode, run `swc format -d bin`, and inspect the source diff. That full `bin/` formatting result
  is the test; do not add compiler suites or format unrelated repository trees.
- Repository prose, backlog, or skill-only work: run the relevant static validator or search and
  inspect the diff. No compiler build is evidence for prose.
- Tool-only work: invoke the changed tool's help and the narrowest harmless command that reaches
  the edited branch. Do not run `tests.swgs` merely because its implementation changed.

### Compiler and runtime changes

| Changed behavior | First boundary |
| --- | --- |
| C++ helper or invariant with a C++ test seam | `swc tools/unittests.swgs dm cpp` |
| lexing | `lexer` suite, focused with `--file-filter` when one standalone input proves it |
| parsing | `parser` suite, focused with `--file-filter` |
| semantic analysis or diagnostics | `sema` suite, focused with `--file-filter` |
| compile-time/JIT execution | `jit` suite |
| runtime safety insertion or panic | `safety` suite in a guarded configuration |
| static sanity analysis | `sanity` suite |
| native lowering, micro backend, ABI, or emitted code | `native` suite in a configuration that executes the path |
| module graph, import, cache, workspace, publication, or cross-module artifact lifetime | `workspace` suite or its exact workspace module reproducer |
| linker, PE/PDB, or debug information | focused C++/native tests plus one real linked consumer when the contract crosses the linker |
| driver command or process launch | the exact command boundary; add a suite only if the defect reduces to it |

Run the regression file first. Extend to its suite only when neighboring cases share the changed
mechanism. Extend to a linked application, reference, or workspace only when the contract crosses
that boundary.

Changes under `bin/runtime` follow behavior, not directory: allocator changes use allocator
tests, panic/safety changes use safety tests, ABI/startup changes use native tests, and lifecycle
across modules uses the workspace suite.

### Standard modules, applications, examples, and the reference

- Test the owning `bin/std` module. Test an importer only when changing public behavior, ABI,
  exported representation, shared runtime state, or a path the owning module cannot activate.
  Do not walk every importer mechanically.
- In an application, run the test file that owns the behavior. Add `build` for module setup,
  packaging, resources, or link changes. Add `smoke` for startup, main-loop, or
  packaged-runtime changes. A local model or widget edit does not require all three.
- Smoke only the changed example or script when its value is that the real program starts.
- Test one reference page with `--file-filter` when it is self-contained. Test the complete
  reference for syntax changes, shared reference infrastructure, or cross-page declarations.
- Use a full application or repository campaign only for a genuinely cross-cutting change or an
  explicitly requested periodic validity pass.

## Focus Test Files Without Dropping Implementation

Use `--test-file <substring>` for `bin/std`, application, example, or reference modules. It
compiles the whole owning module and executes only `#test` functions whose source path matches.
Repeat it to select a union:

```text
swc tools/std.swgs dm test gui --test-file htmlview.test.swg
swc tools/std.swgs dm test gui --test-file htmlview.test.swg --test-file markdownview.test.swg
swc tools/apps.swgs dm test sFileScope --test-file viewer.video.test.swg
```

Use `--file-filter` only for standalone compiler-suite inputs or a self-contained reference page.
It removes non-matching source inputs, so it is unsafe for a module test that needs implementation
files outside the test file.

Prefer a named application test file over all GUI tests:

- HTML parser/layout/rendering: `gui`'s `htmlview.test.swg`, then sFileScope's
  `viewer.html.test.swg` as the concrete file-viewer consumer; do not run the rest of GUI.
- Markdown parser/layout/rendering: `gui`'s `markdownview.test.swg`, then
  `viewer.markdown.test.swg` as the concrete viewer consumer.
- Video codecs/streaming: the matching `video` file (`avi.test.swg`, `y4m.test.swg`, or
  `streaming.test.swg`), then sFileScope's `viewer.video.test.swg` as the concrete player.
- Dialog composition: `dialogs.charter.test.swg`, `dialogs.layout.test.swg`, and the exact dialog
  test such as `messagedlg.test.swg`; use `gui9` only for the required visual inspection.

These are examples of the rule, not a closed routing table. Follow the call path to the nearest
consumer that activates the changed behavior.

## Treat Goldens As Behavioral Evidence

- Any change to rendering, layout, typography, themes, icons, image decoding, or paint commands
  must run the exact test files that own affected text or PNG goldens.
- Inspect every produced `.actual.txt` or `.actual.png` before promotion. A changed pixel outside
  the intended part is a regression or a new finding, not noise.
- Cover each state whose rendering branch changed: palette, DPI, enabled/disabled state, backend,
  or viewport. Do not multiply states that share the same unchanged path.
- When a shared primitive affects many surfaces, select representative goldens for each distinct
  downstream rendering path. Do not substitute every GUI application for that reasoning.
- Promote reviewed outputs with `swc tools/goldens.swgs`; never update a golden merely to make a
  test green.

## Escalate Only On Evidence

Escalate when a focused result reveals a broader contract, the diff changes shared declarations
or artifact layout, the reproducer depends on concurrency or configuration, or no narrower test
can observe the behavior. Do not escalate because a test is cheap, because the change is C++, or
because a path map would have selected it.

After a late focused fix, rerun the failing boundary and any later evidence invalidated by that
fix. Keep earlier independent green evidence.

Stop when every changed behavior has a regression boundary, all selected configurations and
compiler executables are green, affected goldens were inspected, and the final diff adds no
unvalidated path. Report exactly what ran, with compiler executable, program configuration,
filters, and any intentionally unrun broader campaign.
