#global namespace Tool

using Core

// Prints the usage of one tool, which is what `-h` asks for.
public func printUsage(name: string)->s32
{
    switch name
    {
    case "tests":
        @print(
"""
Runs the repository test set, whole or scoped to what changed.

  tests.bat [dm] [changed|plan] [<path>] [options...]

  dm                 use the DevMode compiler
  changed            run only what the working-tree change requires
  plan               print that selection, and run nothing
  <path>             answer for that one file instead of the working tree,
                     which is how the map is asked before a change is made
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --all-cfg          repeat the selected set in all three configurations

Five rungs, cheapest and most specific first: the frontend suites, the code
generation suites, the standard library, the applications and the reference,
then the programs that only prove they start. Each rung runs in every requested
configuration before the next one begins, so a fault only one configuration can
produce reports without waiting for the others to finish.

'changed' maps each changed path to a surface, adds whatever imports a selected
standard library module, and climbs the same ladder carrying only that. A path
matching no surface selects everything, so an unmapped file costs time instead
of coverage.
""")

    case "unittests":
        @print(
"""
Runs the compiler test suites.

  unittests.bat [dm] [<suite>] [options...]

  dm                 use the DevMode compiler, and run the C++ suite
  <suite>            cpp lexer parser sema jit safety sanity native workspace
  -bc <config>       release, debug, or fast-debug (default fast-debug)

Without a suite every suite runs, in the order above. Any other option is
forwarded to the compiler, for instance --seed, --num-cores, or --randomize.
""")

    case "std":
        @print(
"""
Builds or tests the standard library.

  std.bat [dm] [build|test] [<module>] [options...]

  dm                 use the DevMode compiler
  <module>           one of bin/std/modules, for instance core or pixel
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --run-arg <value>  pass a run argument to the tested module

Testing always builds the workspace first. Modules without a unit test are skipped.
""")

    case "examples":
        @print(
"""
Builds, runs, tests, or smokes the examples workspace.

  examples.bat [dm] [build|run|test|smoke] [<module>] [options...]

  dm                 use the DevMode compiler
  <module>           one of bin/examples/modules, for instance gui2 or pixel4
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --frames <count>   bound a run or a smoke to that many frames
  --run-timeout <s>  fail a run or a smoke that outlives that many seconds

  examples.bat run gui2        launch one example
  examples.bat dm test gui2    run its tests with the DevMode compiler

The standard library is built first. 'smoke' proves a program starts and keeps
going for a bounded number of frames, isolated from the machine.
""")

    case "apps":
        @print(
"""
Builds, runs, tests, or smokes the applications workspace.

  apps.bat [dm] [build|run|test|smoke] [<module>] [options...]

  dm                 use the DevMode compiler
  <module>           one of bin/apps/modules, for instance sCrypt or sCapture
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --frames <count>   bound a smoke to that many frames
  --run-arg <value>  an argument for the launched application

  apps.bat run sCrypt          launch one application
  apps.bat dm test sCapture    run its tests with the DevMode compiler

Every command places each application's runtime files beside its executable, so a
packaged application stays launchable after a test pass. 'run' needs a module name
and launches the packaged executable from its own directory.
""")

    case "reference":
        @print(
"""
Builds or tests the executable language reference.

  reference.bat [dm] [build|test] [options...]

  dm                 use the DevMode compiler
  build              compile every page without running its samples
  test               compile and run them (default)
  -bc <config>       release, debug, or fast-debug (default fast-debug)
""")

    case "scripts":
        @print(
"""
Runs one standalone example script, or smokes every one of them.

  scripts.bat [dm] [run|smoke] [<script>] [options...]

  dm                          use the DevMode compiler
  <script>                    a name from bin/examples/scripts, with or without .swgs
  -bc <config>                release, debug, or fast-debug (default fast-debug)
  --run-arg swag.smoke=<n>    bound the run to that many frames

  scripts.bat snake            launch one script
  scripts.bat                  smoke every script
  scripts.bat smoke snake      smoke that one

Naming a script runs it; naming none smokes them all, isolated from the machine.
""")

    case "build":
        @print(
"""
Builds every repository workspace.

  build.bat [dm] [options...]

  dm                 use the DevMode compiler
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --all-cfg          repeat the whole build in all three configurations

Covers the standard library, the examples, the applications, the language
reference, and the multi-module workspace suite.
""")

    case "format":
        @print(
"""
Formats every Swag source workspace in the repository, in place.

  format.bat [dm] [options...]

This rewrites tracked sources. It is a maintenance step, never a test.
""")

    case "goldens":
        @print(
"""
Promotes the snapshots a failing test left behind into their goldens.

  goldens.bat

A golden mismatch writes '<name>.actual.txt' or '<name>.actual.png' next to its
reference and fails. Once reviewed, this moves every actual over its golden.
""")

    case "web":
        @print(
"""
Regenerates the brand assets and the complete website under web/.

  web.bat [dm] [options...]

Cuts the mark, the icons and the favicons first, then documents the bin/std and
bin/reference workspaces.
""")

    case "scrypt":
        @print(
"""
Runs the privileged sCrypt/WinFsp end-to-end sandbox.

  scrypt.bat [dm]

Builds sCrypt with the SCrypt.Integration tag, runs it, prints its report, then
rebuilds a normal sCrypt. It mounts a real volume, so it stays out of tests.bat.
""")

    case "vsix":
        @print(
"""
Packages the VSCode extension after refreshing its generated images.

  vsix.bat

Install Node.js, then 'npm install -g vsce', before using this.
""")

    case "setup":
        @print(
"""
Registers bin/ in the current user's environment.

  setup.bat
""")

    case "bench":
        @print(
"""
Runs or regenerates the cross-language performance campaign.

  bench.bat                             a full campaign
  bench.bat --label "what changed"      the same, with a note in the history
  bench.bat --quick                     smoke test, one repetition, not recorded
  bench.bat --report-only               regenerate the page, measure nothing

See bench/README.md before changing anything about how it measures.
""")

    default:
        @print("No usage is recorded for '", name, "'.\n")
        return 1
    }

    return 0
}
