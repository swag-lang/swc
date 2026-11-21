# Compiler Command Backlog

This file owns behavior shared across swc commands, including command effects and the boundary between compiler records and launched-program output. Command-specific behavior belongs in the corresponding command file.

### compiler.command.001 — An autonomous caller cannot tell what a command may execute or change

- Evidence: compiling Swag can execute `#run` and JIT code; `run`, `test`, format, clean, tool
  setup, and example commands have different filesystem, process, and machine-configuration effects.
  `Command.DryRun.cpp` already reports a suppressed-execution plan, and `syntax` stops after parsing.
  What is missing is a discoverable command effect contract that can answer before any project code executes.
- Intent: give all callers an explicit effect model. Read-only discovery and parsing have a defined
  no-execution contract; planning reports what would execute or change; mutation and launch commands
  name their targets before acting. Existing safe defaults such as `new` refusing collisions become
  part of the public contract.
- Next: encode the existing dry-run and syntax boundaries, then inventory each command's reads,
  writes, process launches, compile-time execution, native
  linking, cache use, and shell/registry changes. Define safe inspection modes and the boundary at
  which semantic analysis necessarily requires user code. Report the actual blocked phase
  and its source or module on read-only requests.
- Done when: an autonomous caller can enumerate a command's effects without executing user
  code, choose a documented non-executing inspection path, and receive a precise report before a
  command writes outside the project or configured cache roots, launches an artifact, contacts a
  network endpoint, or edits user shell configuration.
- Related: compiler.command.help.001, compiler.command.002, platform.portability.009,
  platform.portability.080.

### compiler.command.002 — Separate program output from compiler records

- Evidence: a program run by the JIT writes unframed output to the same stdout as the
  compiler. The current line format is described in
  [the message guide](../.agents/skills/write-swag-compiler-messages/SKILL.md).
- Next: separate the program byte stream from driver records on JIT and native paths.
  Use a distinct channel for runtime output, and attach captured failure output to its
  owning test. Keep one readable compiler format, publish its grammar version in `swc info`
  and test the located diagnostic, stage and final command boundaries.
- Done when: program output can be consumed independently, text resembling a compiler
  record stays program output, and failures and final command results remain identifiable
  when a child exits early or a JIT test panics.
- Related: compiler.frontend.006, compiler.query.001, compiler.command.test.001, compiler.command.001.
