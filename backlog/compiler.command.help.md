# Help and Examples Command Backlog

This file owns command help, the first-project path, and discovery and reuse of runnable examples.

### compiler.command.help.001 — The first command does not close the first-program loop

- Evidence: `swc help` shows `new script`, `new module` and their follow-up commands, but its
  links lead to the website and GitHub's moving `master` branch
  (`CommandLineParser.Help.cpp`). `swc new` embeds only a script and a module starter
  (`Command.New.cpp`). An offline user has no local route from a command,
  an error, or a generated starter to version-matched explanation.
- Next: give every command a local documentation topic in `swc help <command>`, with
  examples, defaults, side effects and destructive behavior. Add named embedded templates
  to `swc new` (workspace executable, tests, command-line arguments, files, errors, minimal
  GUI). Include the first test or verification command for each starter. Extend the existing
  collision-safe creation result with expected output and a local topic. Reuse `--dry-run`
  for the creation plan.
- Done when: an offline newcomer can complete a script and workspace tutorial with
  `swc` and its local resources, inspect a build before it runs, and recover from an intentional syntax error and a
  missing-toolchain error without a browser or repository.
- Related: compiler.command.doc.011, compiler.command.help.002, compiler.command.doc.012, language.design.049.

### compiler.command.help.002 — Examples are repository files, not a runnable catalogue

- Evidence: useful scripts, module demonstrations, applications, and tested reference pages exist
  below `bin/examples` and `bin/reference`, but their discovery depends on the repository tree and
  GitHub. Names alone do not tell a beginner whether an example writes files, opens a window,
  requires assets, imports native libraries, or is the right minimum for one concept.
- Intent: turn the repository examples into a local catalogue with `list`, `show`, `copy`, `run`, and
  `test` operations. Each example names its learning goal, difficulty, required modules and host
  capabilities, source/assets, expected output, runtime bound, and exact verification command.
- Constraints:
  - The catalogue supplies all assets each example needs and runs without accessing
    temporary developer paths or the network.
  - `copy` creates a user-owned project and refuses collisions; `show` is read-only; `run` makes
    its execution and output location explicit.
  - The catalogue begins with small composable examples before games and applications. Every
    advertised example is built or tested with the matching compiler.
- Next: turn the repository examples into a local catalogue with list, show, copy, run, and test operations
  and the stated provenance and limits.
- Done when: a user can find, inspect, copy, run, and test one example for scripts, workspaces,
  imports, tests, errors, compile-time execution, core collections, and GUI from the same catalogue. The catalogue gives a useful prerequisite report rather than attempting an impossible
  native or GUI example.
- Related: compiler.command.help.001, compiler.command.doc.011, compiler.command.doc.012.
