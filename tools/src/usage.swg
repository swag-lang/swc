#global namespace Tool

using Core

// Prints the usage of one tool, which is what `-h` asks for.
public func printUsage(name: string)->s32
{
    switch name
    {
    case "tests":
        Console.print("""
Runs the repository test set, whole or scoped to what changed.

  swc tools/tests.swgs [dm] [changed|plan] [<path>] [options...]

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
        Console.print("""
Runs the compiler test suites.

  swc tools/unittests.swgs [dm] [<suite>] [options...]

  dm                 use the DevMode compiler, and run the C++ suite
  <suite>            cpp lexer parser sema jit safety sanity native workspace
  -bc <config>       release, debug, or fast-debug (default fast-debug)

Without a suite every suite runs, in the order above. Any other option is
forwarded to the compiler, for instance --seed, --num-cores, or --randomize.
Every tool keeps a few cores free for the rest of the machine unless the
caller passes its own --num-cores.
""")

    case "portability":
        Console.print("""
Checks the dependency boundary between portable bin code and native host code.

  swc tools/portability.swgs

The audit reads sources only. It rejects native imports, '#os' branches, foreign
declarations, native identifiers, and native public signatures outside the exact
host, interoperability, dispatch, and adapter paths recorded by the policy.
""")

    case "std":
        Console.print("""
Builds or tests the standard library.

  swc tools/std.swgs [dm] [build|test] [<module>] [options...]

  dm                 use the DevMode compiler
  <module>           one of bin/std/modules, for instance core or pixel
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --run-arg <value>  pass a run argument to the tested module

Testing always builds the workspace first. Modules without a unit test are skipped.
""")

    case "examples":
        Console.print("""
Builds, runs, tests, or smokes the examples workspace.

  swc tools/examples.swgs [dm] [build|run|test|smoke] [<module>] [options...]

  dm                 use the DevMode compiler
  <module>           one of bin/examples/modules, for instance gui2 or pixel4
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --frames <count>   bound a run or a smoke to that many frames
  --run-timeout <s>  fail a run or a smoke that outlives that many seconds

  swc tools/examples.swgs run gui2        launch one example
  swc tools/examples.swgs dm test gui2    run its tests with the DevMode compiler

The standard library is built first. 'smoke' proves a program starts and keeps
going for a bounded number of frames, isolated from the machine.
""")

    case "apps":
        Console.print("""
Builds, runs, tests, or smokes one or every application workspace.

  swc tools/apps.swgs [dm] [build|run|test|smoke] [<application>] [options...]

  dm                 use the DevMode compiler
  <application>      a workspace under bin/apps, for instance sVaultDrive or sSnapForge
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --frames <count>   bound a smoke to that many frames
  --run-arg <value>  an argument for the launched application

  swc tools/apps.swgs run sVaultDrive          launch one application
  swc tools/apps.swgs dm test sSnapForge    run its tests with the DevMode compiler

Every command covers every module in the selected application workspace and places
its runtime files beside the executable. 'run' needs an application name
and launches the packaged executable from its own directory.
""")

    case "reference":
        Console.print("""
Builds or tests the executable language reference.

  swc tools/reference.swgs [dm] [build|test] [options...]

  dm                 use the DevMode compiler
  build              compile every page without running its samples
  test               compile and run them (default)
  -bc <config>       release, debug, or fast-debug (default fast-debug)
""")

    case "scripts":
        Console.print("""
Runs one standalone example script, or smokes every one of them.

  swc tools/scripts.swgs [dm] [run|smoke] [<script>] [options...]

  dm                          use the DevMode compiler
  <script>                    a name from bin/examples/scripts, with or without .swgs
  -bc <config>                release, debug, or fast-debug (default fast-debug)
  --run-arg swag.smoke=<n>    bound the run to that many frames

  swc tools/scripts.swgs snake            launch one script
  swc tools/scripts.swgs                  smoke every script
  swc tools/scripts.swgs smoke snake      smoke that one

Naming a script runs it; naming none smokes them all, isolated from the machine.
""")

    case "build":
        Console.print("""
Builds every repository workspace.

  swc tools/build.swgs [dm] [options...]

  dm                 use the DevMode compiler
  -bc <config>       release, debug, or fast-debug (default fast-debug)
  --all-cfg          repeat the whole build in all three configurations

Covers the standard library, the examples, the applications, the language
reference, and the multi-module workspace suite.
""")

    case "format":
        Console.print("""
Formats every Swag source workspace in the repository, in place.

  swc tools/format.swgs [dm] [options...]

This rewrites tracked sources. It is a maintenance step, never a test.
""")

    case "goldens":
        Console.print("""
Promotes the snapshots a failing test left behind into their goldens.

  swc tools/goldens.swgs

A golden mismatch writes '<name>.actual.txt' or '<name>.actual.png' next to its
reference and fails. Once reviewed, this moves every actual over its golden.
""")

    case "web":
        Console.print("""
Regenerates the brand assets and the complete website under web/.

  swc tools/web.swgs [dm] [options...]

Cuts the mark, the icons and the favicons first, then documents the bin/std and
bin/reference workspaces.
""")

    case "vaultdrive":
        Console.print("""
Runs the privileged sVaultDrive/WinFsp end-to-end sandbox.

  swc tools/vaultdrive.swgs [dm]

Builds sVaultDrive with the SVaultDrive.Integration tag, runs it, prints its report, then
rebuilds a normal sVaultDrive. It mounts a real volume, so it stays out of tests.swgs.
""")

    case "vsix":
        Console.print("""
Packages the VSCode extension after refreshing its generated images.

  swc tools/vsix.swgs

Install Node.js, then 'npm install -g vsce', before using this.
""")

    case "setup":
        Console.print("""
Registers bin/ in the current user's environment, and claims the .swgs extension.

  swc tools/setup.swgs

Puts bin/ on PATH, points SWAG_PATH at it, and hands .swgs to bin/swc.exe for the
current user, so a double-click runs a script.
""")

    case "bench":
        Console.print("""
Runs or regenerates the cross-language performance campaign.

  swc tools/bench.swgs                             a full campaign
  swc tools/bench.swgs --label "what changed"      the same, with a note in the history
  swc tools/bench.swgs --quick                     smoke test, one repetition, not recorded
  swc tools/bench.swgs --report-only               regenerate the page, measure nothing

See bench/README.md before changing anything about how it measures.
""")

    default:
        Console.println("No usage is recorded for '", name, "'.")
        return 1
    }

    return 0
}
