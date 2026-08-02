#global public
#global namespace Env

using Core.Errors

/*
Process-wide isolation from real machine state.

A test or a smoke run must not be able to reach the files, the settings or the desktop of
the person running it. The sandbox is what makes that structural rather than a matter of
each test remembering to redirect: once it is armed, [[Env.getSpecialDirectory]] answers
inside the sandbox, every write outside it fails, and the system mutations an application
performs on startup are refused.

It is armed by the runtime from the process command line before any `#init`, `#premain` or
`#main` code runs, so an application needs no knowledge of it.

> ATTENTION:
> A refused operation fails; it is never a silent no-op. Isolation that quietly does nothing
> produces the same wrong-but-green result the sandbox exists to prevent.
*/
private var g_SandboxRoot: String
private var g_Sandboxed:   bool
private var g_DeniedCount: u64

// Run argument the compiler passes to a generated executable to isolate it. Either on its
// own, letting the process pick a private root, or followed by '=' and an explicit one.
private const SandboxArg = "swag.sandbox"

// Run argument bounding a smoke run, as 'swag.smoke=<frames>'.
private const SmokeArg = "swag.smoke"

// Frames a smoke run renders when the argument carries no usable count.
private const DefaultSmokeFrames = 50'u32

// Builds a private sandbox root for this process under the real temporary directory.
//
// Computed before anything is armed, so the temporary directory it starts from is the real one
// and not a redirection of itself. The name comes from the process id rather than a random
// value: this runs as the first init hook of the program, ahead of whatever seeds a generator,
// and it makes the folder easy to match to a run that failed.
private func defaultSandboxRoot()->String
{
    var result = Path.combine(getSpecialDirectory(.Temp).toString(), "swag-sandbox")
    var name   = String.from("run-")
    name += Format.toString("%", currentProcessId())
    result = Path.combine(result.toString(), name.toString())
    return result
}

// Arms the sandbox before any application code runs, when the launcher asked for it.
//
// 'swc test' and 'swc smoke' hand the root down as a run argument, so isolation is a property
// of how the process was started rather than something an application opts into. This runs as
// a module init hook, ahead of every '#init', '#premain' and '#main' in the program.
#init
{
    let request = findRunArgument(SandboxArg)
    if request.found
    {
        var root = request.value
        if root.isEmpty() do
            root = defaultSandboxRoot()

        catch enterSandbox(root.toString()) else
        {
            // Continuing unsandboxed would let the run reach real machine state, which is
            // exactly what the caller asked to prevent.
            @print("[swag.sandbox] cannot arm the sandbox at '", root, "'\n")
            abortUnsandboxed()
        }
    }
}

// Stops a run that asked to be isolated and could not be.
private func abortUnsandboxed(loc = #callerlocation)
{
    @panic("sandbox setup failed", loc)
}

// Names a category of machine state an application mutates outside its own files.
enum SystemMutation
{
    ApplicationRegistration     // Registering the application with the shell.
    FileAssociation             // Claiming a file extension.
    AutoStart                   // Starting with the session.
    GlobalHotKey                // Reserving a system-wide keyboard shortcut.
    TrayIcon                    // Placing an icon in the notification area.
}

// Arms the sandbox at `root`, which becomes the answer to every special-directory query.
//
// `root` is created when missing. Arming twice with the same root is accepted; changing an
// armed root is not, because code may already hold paths derived from the previous one.
func enterSandbox(root: string) fail
{
    if @countof(root) == 0 do
        fail BadParameterError{"a sandbox needs a root directory"}

    let normalized = absolutePath(root)

    if g_Sandboxed
    {
        if normalized == g_SandboxRoot do
            return
        fail BadParameterError{"the sandbox root cannot change once armed"}
    }

    try createDirectoryTree(normalized.toString())

    g_SandboxRoot = normalized
    g_Sandboxed   = true
}

// Creates `path` along with every missing directory above it.
//
// The platform call only creates one level, and a sandbox root normally sits two or more
// below the temporary directory.
private func createDirectoryTree(path: string) fail
{
    if @countof(path) == 0 or Directory.exists(path) do
        return

    let parent = Path.directoryName(path)
    if parent != null and @countof(parent) != 0 and parent != path do
        try createDirectoryTree(parent)

    try Directory.create(path)
}

// Reports whether the process is isolated from real machine state.
func isSandboxed()->bool => g_Sandboxed

// Reports whether the process is a smoke run: the real program, bounded by its launcher.
//
// Code driving its own loop instead of [[Gui.Application.run]] asks this to know when to stop.
// Nothing else should branch on it: a smoke run must exercise the same paths as a real one.
func isSmokeRun()->bool => smokeFrames() != 0

// Returns how many frames a smoke run renders before stopping, or zero outside one.
//
// A smoke run proves the real program starts and keeps running; the bound belongs to whoever
// launched it, so an application never has to recognize that it is being exercised.
func smokeFrames()->u32
{
    let request = findRunArgument(SmokeArg)
    if !request.found do
        return 0

    // A marker with no usable count still means a bounded run, so fall back rather than
    // returning zero, which would read as "not a smoke run" and let the program run forever.
    let frames = catch StrConv.toU32(request.value.toString())
    return frames != 0 ? frames : DefaultSmokeFrames
}

// Returns the sandbox root, or an empty string when the process is not sandboxed.
func sandboxRoot()->string => g_SandboxRoot.toString()

// Returns how many system mutations have been refused so far.
//
// A smoke run reports this: an application that still reaches for the registry or the shell
// on startup is not yet isolated, even though nothing failed.
func deniedSystemMutations()->u64 => g_DeniedCount

// Reports whether `mutation` must be refused, recording it when so.
//
// Call this at the boundary that performs the mutation and return without doing anything
// when it answers true. This is the one place a refusal is silent to the caller, because
// the caller is std itself and the tally is what surfaces it.
internal func denySystemMutation(mutation: SystemMutation)->bool
{
    discard mutation
    if !g_Sandboxed do
        return false
    g_DeniedCount += 1
    return true
}

// Reports whether `path` names `root` itself or something below it.
//
// Both sides are resolved and normalized first, so a relative path, a mixed separator style
// or a difference in case cannot smuggle a location past the check.
func isInsideDirectory(root: string, path: string)->bool
{
    if @countof(root) == 0 do
        return false

    let full = absolutePath(path).toLower()
    let base = absolutePath(root).toLower()
    let f    = full.toString()
    let r    = base.toString()

    if @countof(f) < @countof(r) do
        return false
    if f[0 until @countof(r)] != r do
        return false

    // A prefix match is not containment: 'C:/tmp/sandboxed' starts with 'C:/tmp/sandbox'.
    if @countof(f) == @countof(r) do
        return true
    return Path.isDirectorySeparator(f[@countof(r)])
}

// Reports whether `path` is inside the sandbox. Answers true when nothing is armed.
func isInsideSandbox(path: string)->bool
{
    if !g_Sandboxed do
        return true
    return isInsideDirectory(g_SandboxRoot.toString(), path)
}

// Returns the sandbox stand-in for a well-known system directory, creating it on demand.
//
// Each kind gets its own sub-folder, so an application that puts its data under the documents
// folder and its settings under the application-data folder still sees two distinct places.
internal func sandboxSpecialDirectory(what: SpecialDirectory)->String
{
    var kind   = what
    let name   = Reflection.enumName(SpecialDirectory, &kind, fullyQualified: false)
    var result = Path.combine(g_SandboxRoot.toString(), name.toString())

    Path.normalize(&result)
    if !Directory.exists(result) do
        discard catch Directory.create(result)
    return result
}

// Fails when `path` would be written outside the sandbox.
//
// Every operation in [[Core.File]] and [[Core.Directory]] that creates, modifies or removes
// something calls this first. Outside a sandbox it is a single boolean test.
internal func guardWrite(path: string) fail
{
    if !g_Sandboxed do
        return
    if isInsideSandbox(path) do
        return
    fail SandboxError{"refusing to write outside the sandbox", path: absolutePath(path).toString()}
}
