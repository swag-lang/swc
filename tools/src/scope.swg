#global namespace Tool

using Core

/*
What a working-tree change actually requires.

A path maps to a surface, a surface maps to work, and the work of every changed path is unioned.
A path that matches no surface selects the whole campaign: an unknown file has to cost more than
it saves, or the map silently stops covering the repository as it grows.
*/
public struct Scope
{
    all:         bool               // The whole campaign, because something unmapped or universal changed.
    doc:         bool               // Regenerate the site and read the diff.
    format:      bool               // Reformat the sources and read the diff.
    reference:   bool               // The executable language reference.
    hasStd:      bool               // At least one standard library module is selected.
    allApps:     bool               // Every application, because the emitted image changed.
    count:       u64                // How many paths were classified.
    unknown:     String             // The first path that matched no surface.
    warnProject: String             // A project file that may carry a compile flag.
    suites:      HashSet'String     // Compiler suites to run.
    std:         HashSet'String     // Standard library modules to test.
    apps:        HashSet'String     // Applications to test and smoke.
    examples:    HashSet'String     // Examples to smoke.
    scripts:     HashSet'String     // Scripts to smoke.
}

// Resolves which part of the campaign the working tree, or one named path, requires.
public func resolveScope(context: *Context, paths: const [..] String)->Scope fail
{
    var result: retval

    if @countof(paths) != 0
    {
        for path in paths do
            classify(&result, path.toString())
    }
    else
    {
        // 'diff HEAD' covers the staged and the unstaged half at once; untracked files are the
        // other half of a working tree, and a brand new test file is exactly the one that must
        // not be missed.
        for line in gitLines(context, ["diff", "--name-only", "HEAD"]) do
            classify(&result, line.toString())
        for line in gitLines(context, ["ls-files", "--others", "--exclude-standard"]) do
            classify(&result, line.toString())
    }

    if result.allApps
    {
        for name in context.workspaceModules("apps") do
            discard result.apps.add(name)
    }

    if result.count == 0 or result.all do
        return result

    // Nothing consumes an example, a script or an application, so the graph is only worth
    // walking when a standard library module is in the selection.
    if !result.hasStd do
        return result

    closeStandardLibrary(context, &result)
    closeConsumers(context, &result)
    return result
}

private func gitLines(context: *Context, arguments: const [..] string)->Array'String
{
    var result: retval

    var command: Arguments
    command.add(["-C", context.root.toString()])
    command.add(arguments)

    let output = catch context.captureProgram("git.exe", command) as err
    if err != null do
        return result

    for line in Tokenize.splitLines(output.toString())
    {
        let trimmed = Latin1.trim(line)
        if @countof(trimmed) != 0 do
            result.add(String.from(trimmed))
    }

    return result
}

// Maps one repository-relative path to the surface it belongs to.
private func classify(scope: *Scope, rawPath: string)
{
    if @countof(rawPath) == 0 do
        return

    var path = String.from(rawPath)
    path.replace("\\", "/")
    let text = path.toString()
    scope.count += 1

    // The two commands that sit beside the compiler rather than inside it. Neither is on the
    // path that compiles a program, so neither can break one, and both are validated by
    // regenerating their output and reading the diff.
    if under(text, "src/Doc/") or under(text, "src/Main/Command/Command.Doc")
    {
        scope.doc = true
        return
    }

    if under(text, "src/Format/") or under(text, "src/Main/Command/Command.Format") or under(text, "src/Unittest/Format/")
    {
        scope.format = true
        discard scope.suites.add(String.from("cpp"))
        return
    }

    // A C++ test cannot change what the compiler does.
    if under(text, "src/Unittest/")
    {
        discard scope.suites.add(String.from("cpp"))
        return
    }

    // A formatting configuration changes how sources are written, never what they mean.
    if endsWith(text, ".swc-format") or endsWith(text, ".swc-format/")
    {
        scope.format = true
        return
    }

    // Repository metadata: what git tracks, how it stores it, and how C++ is written. None of it
    // reaches a compiled program.
    if endsWith(text, ".gitignore") or endsWith(text, ".gitattributes") or endsWith(text, ".clang-format") or endsWith(text, ".DotSettings") do
        return

    // Emitting the image and its debug information is the one compiler area a JIT-only suite
    // cannot see and a smoke run cannot say anything useful about: what proves it is a real
    // link, which the native suite, the applications and the reference all perform.
    if under(text, "src/Backend/Linker/") or under(text, "src/Backend/Debug/")
    {
        discard scope.suites.add(String.from("native"))
        discard scope.suites.add(String.from("workspace"))
        scope.reference = true
        scope.allApps   = true
        return
    }

    // Sema, code generation, the micro backend, the JIT, the runtime support and the driver all
    // sit under every compiled program. Nothing narrower than the whole campaign is honest.
    if under(text, "src/") or under(text, "bin/runtime/")
    {
        scope.all = true
        return
    }

    if under(text, "bin/std/modules/")
    {
        scope.hasStd = true
        discard scope.std.add(segmentAt(text, 16, "/"))
        return
    }

    if under(text, "bin/examples/modules/")
    {
        discard scope.examples.add(segmentAt(text, 21, "/"))
        return
    }

    // A script is named by its first dot segment, so 'calc.symbols.swg' selects 'calc'.
    if under(text, "bin/examples/scripts/")
    {
        discard scope.scripts.add(segmentAt(text, 21, "."))
        return
    }

    if under(text, "bin/apps/modules/")
    {
        discard scope.apps.add(segmentAt(text, 17, "/"))
        return
    }

    if under(text, "bin/unittests/workspace/")
    {
        discard scope.suites.add(String.from("workspace"))
        return
    }

    if under(text, "bin/unittests/errors/")
    {
        discard scope.suites.add(segmentAt(text, 21, "/"))
        return
    }

    if under(text, "bin/unittests/")
    {
        discard scope.suites.add(segmentAt(text, 14, "/"))
        return
    }

    if under(text, "bin/reference/")
    {
        scope.reference = true
        return
    }

    // Nothing here is compiled into anything the campaign runs.
    if under(text, "tools/") or under(text, ".agents/") or under(text, "backlog/") or under(text, ".vscode/") or under(text, "bench/") do
        return

    // The generated site and the sources that cut it are the doc surface.
    if under(text, "web/")
    {
        scope.doc = true
        return
    }

    // A repository document explains the work; it never changes what the work does.
    if endsWith(text, ".md") do
        return

    // A project file almost always changes because a source was added or removed, and those
    // sources classify themselves. It can also carry a compile flag, which nothing here can tell
    // apart, so the caller is told rather than the whole campaign being charged for the common
    // case.
    if endsWith(text, ".sln") or endsWith(text, ".filters") or endsWith(text, ".vcxproj")
    {
        scope.warnProject = path
        return
    }

    scope.all = true
    if scope.unknown.isEmpty() do
        scope.unknown = path
}

private func under(path: string, prefix: string)->bool
{
    return Utf8.startsWith(cast(const [..] u8) path, prefix, .Latin1NoCase)
}

private func endsWith(path: string, suffix: string)->bool
{
    return Utf8.endsWith(cast(const [..] u8) path, suffix, .Latin1NoCase)
}

// Returns the name that follows a surface prefix, up to the first `delimiter`.
private func segmentAt(path: string, prefixLength: u64, delimiter: string)->String
{
    if @countof(path) <= prefixLength do
        return String.from("")

    let rest  = path[prefixLength until @countof(path)]
    let index = Utf8.indexOf(cast(const [..] u8) rest, delimiter)
    if index == Swag.U64.Max do
        return String.from(rest)
    return String.from(rest[0 until index])
}

// A standard library module that imports a selected one is selected too.
//
// The graph is declared by the `#import` lines of each `module.swg`, so nothing here is a
// hand-kept table. Four passes reach a fixed point on a graph whose longest chain is
// win32 - core - pixel - gui.
private func closeStandardLibrary(context: *Context, scope: *Scope)
{
    for 4
    {
        for name in context.workspaceModules("std")
        {
            if scope.std.contains(name) do
                continue
            if importsSelectedModule(context, scope, "std", name.toString()) do
                discard scope.std.add(name)
        }
    }
}

// Whatever consumes a selected standard library module has to be exercised against it.
private func closeConsumers(context: *Context, scope: *Scope)
{
    for name in context.workspaceModules("examples")
    {
        if !scope.examples.contains(name) and importsSelectedModule(context, scope, "examples", name.toString()) do
            discard scope.examples.add(name)
    }

    for name in context.workspaceModules("apps")
    {
        if !scope.apps.contains(name) and importsSelectedModule(context, scope, "apps", name.toString()) do
            discard scope.apps.add(name)
    }

    let scriptsDir = Path.combine(context.workspacePath("examples").toString(), "scripts")
    let entries    = catch Directory.enumerateFiles(scriptsDir.toString(), ".swgs") as err
    if err == null
    {
        for entry in entries
        {
            let name = String.from(Path.fileNameWithoutExtension(entry.fullname.toString()) orelse "")
            if !scope.scripts.contains(name) and importsSelected(scope, entry.fullname.toString()) do
                discard scope.scripts.add(name)
        }
    }

    if scope.std.contains(String.from("core")) do
        scope.reference = true
}

private func importsSelectedModule(context: *Context, scope: *Scope, workspace: string, name: string)->bool
{
    let moduleFile = Path.combine(context.workspacePath(workspace).toString(), "modules", name, "module.swg")
    return importsSelected(scope, moduleFile.toString())
}

// Reports whether a source imports a standard library module the scope already holds.
//
// An import reads `#import("name")` or `#import("name", location: "...")`, and the line is
// indented whenever it sits inside a conditional block, so the name is read rather than matched.
private func importsSelected(scope: *Scope, sourceFile: string)->bool
{
    let content = catch File.readAllText(sourceFile) as err
    if err != null do
        return false

    for line in Tokenize.splitLines(content.toString())
    {
        let start = Utf8.indexOf(cast(const [..] u8) line, "#import(\"")
        if start == Swag.U64.Max do
            continue

        let after = line[start + 9 until @countof(line)]
        let stop  = Utf8.indexOf(cast(const [..] u8) after, "\"")
        if stop == Swag.U64.Max do
            continue

        if scope.std.contains(String.from(after[0 until stop])) do
            return true
    }

    return false
}
