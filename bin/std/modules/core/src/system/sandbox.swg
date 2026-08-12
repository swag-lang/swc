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

A run may also be granted a *corpus*: one directory outside the root that stays writable, for a
test whose reference data lives with its source. See [[Env.grantCorpus]].

> ATTENTION:
> A refused operation fails; it is never a silent no-op. Isolation that quietly does nothing
> produces the same wrong-but-green result the sandbox exists to prevent.
*/
private var g_SandboxRoot: String
private var g_CorpusRoot: String
private var g_Sandboxed: bool
private var g_DefaultRoot: bool
private var g_DeniedCount: u64

// Run argument the compiler passes to a generated executable to isolate it. Either on its
// own, letting the process pick a private root, or followed by '=' and an explicit one.
private const SandboxArg = "swag.sandbox"

// Run argument granting a corpus, as 'swag.sandbox.corpus=<directory>'. The compiler's 'test'
// command passes the module or workspace whose tests are running.
private const CorpusArg = "swag.sandbox.corpus"

// Run argument bounding a smoke run, as 'swag.smoke=<frames>'.
private const SmokeArg = "swag.smoke"

// Frames a smoke run renders when the argument carries no usable count.
private const DefaultSmokeFrames = 50'u32

// Default-root names the arming hook tries before giving up: the plain process-id name first,
// then the fallback siblings for when a leftover under a name refuses to clear.
private const MaxDefaultRootNames = 4'u32

// Builds a private sandbox root for this process under the real temporary directory.
//
// The starting point is read from the machine rather than through [[Env.getSpecialDirectory]],
// which answers inside the sandbox once one is armed. A process that also executes code at
// compile time runs this hook more than once, and a root computed through the redirection would
// nest a second one under the first, which [[Env.enterSandbox]] rejects as a change of root.
// Reading the real directory makes the answer the same on every pass, which is what turns a
// repeated arming into the no-op it is meant to be.
//
// The name comes from the process id rather than a random value: this runs as the first init
// hook of the program, ahead of whatever seeds a generator, and it makes the folder easy to
// match to a run that failed. A nonzero `ordinal` names a sibling of that root: the fallback
// the arming hook adopts when the leftover under the plain name refuses to clear.
internal func defaultSandboxRoot(ordinal: u32 = 0)->String
{
    var result = Path.combine(realSpecialDirectory(.Temp).toString(), "swag-sandbox")
    var name   = String.from("run-")
    name += Format.toString("%", currentProcessId())
    if ordinal != 0
    {
        name += "-"
        name += Format.toString("%", ordinal)
    }

    result = Path.combine(result.toString(), name.toString())
    return result
}

// Removes what a dead run left at `root`, so the run adopting that name starts on an empty one.
internal func clearLeftoverDefaultRoot(root: string) fail
{
    if Directory.exists(root) do
        try Directory.delete(root, recurse: true)
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
        var root      = request.value
        let isDefault = root.isEmpty()
        if isDefault
        {
            if g_Sandboxed
            {
                // A second arming pass adopts whatever the first pass picked: the default name
                // may have fallen back to a sibling, and recomputing it here would read as a
                // change of root.
                root = g_SandboxRoot
            }
            else
            {
                // The operating system reuses process ids and the default root is named after
                // this one, so a dead run whose id came around again may have left files here.
                // Adopting them would hand this run that run's state — the opposite of what the
                // sandbox promises — so the root has to start empty. Only the default root is
                // ever cleared: no live process can hold this id, while an explicit root belongs
                // to the launcher. The clear itself can still fail while a third party — an
                // indexer, a cleaner walking the temporary directory — holds handles inside the
                // leftover, and that hold says nothing about this run: fall back to a fresh
                // sibling instead of dying, leaving the leftover findable for the run it names.
                var adopted = false
                for attempt in MaxDefaultRootNames
                {
                    root    = defaultSandboxRoot(cast(u32) attempt)
                    adopted = true
                    catch clearLeftoverDefaultRoot(root.toString()) else
                    {
                        adopted = false
                    }

                    if adopted do
                        break
                }

                if !adopted
                {
                    @print("[swag.sandbox] cannot clear the leftover sandbox root at '", root.toString(), "', nor adopt a sibling\n")
                    abortUnsandboxed()
                }
            }
        }

        catch enterSandbox(root.toString()) else
        {
            // Continuing unsandboxed would let the run reach real machine state, which is
            // exactly what the caller asked to prevent. The message is the only trace left
            // before the run dies, so it names both roots: that is what tells an unusable
            // request apart from a second arming that disagrees with the first.
            @print("[swag.sandbox] cannot arm the sandbox at '", root.toString(), "'")
            if g_Sandboxed do
                @print(", already armed at '", g_SandboxRoot.toString(), "'")
            @print("\n")
            abortUnsandboxed()
        }

        g_DefaultRoot = isDefault
    }

    let corpus = findRunArgument(CorpusArg)
    if corpus.found
    {
        catch grantCorpus(corpus.value.toString()) else
        {
            // A grant that does not hold is worse than no grant at all: the run keeps going and
            // every recording it was launched to make is refused one by one, which reads as a
            // test failure rather than as a launcher mistake.
            @print("[swag.sandbox] cannot grant the corpus at '", corpus.value.toString(), "'\n")
            abortUnsandboxed()
        }
    }
}

// Removes the private root once the run that picked it is over.
//
// This runs as a drop hook of the program's deepest dependency, after every other module's
// '#drop', so nothing can still write inside the root. Only the default root is removed — an
// explicit one belongs to the launcher — and only in a generated executable: hosted by the
// compiler, the module set may arm again later and expects the root it left. Best effort by
// design: a file still held open must not turn the run that owns it into a failure, and a root
// left behind is cleared by the next run that draws the same process id. A run that dies before
// its drop hooks keeps its root, which is what makes a failure findable afterwards.
#drop
{
    if !g_Sandboxed or !g_DefaultRoot or (@rtflags & .FromCompiler) do
        return
    discard catch Directory.delete(g_SandboxRoot.toString(), recurse: true)
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

// Grants `root` as the corpus: the one directory outside the sandbox a run may still write.
//
// A test keeps its reference data next to its own source, so recording one — creating a snapshot
// that does not exist yet, or leaving the produced one beside the reference it diverged from —
// means writing into the sources under test. The sandbox refuses that, and it is right to: the
// escape belongs to whoever launched the run, not to the test asking for it. `swc test` grants
// the module or workspace it is testing, and nothing else; the machine stays out of reach.
//
// `root` must already exist. Granting twice with the same root is accepted; changing a granted
// root is not, because code may already hold paths derived from the previous one.
func grantCorpus(root: string) fail
{
    if @countof(root) == 0 do
        fail BadParameterError{"a corpus needs a root directory"}

    let normalized = absolutePath(root)

    if !g_CorpusRoot.isEmpty()
    {
        if normalized == g_CorpusRoot do
            return
        fail BadParameterError{"the corpus root cannot change once granted"}
    }

    // Never created, unlike the sandbox root: a corpus is an existing source tree, and a missing
    // one means the launcher named the wrong place rather than a place still to make.
    if !Directory.exists(normalized) do
        fail FileNotFoundError{"the corpus root does not exist", fileName: normalized.toString()}

    g_CorpusRoot = normalized
}

// Reports whether the process is isolated from real machine state.
func isSandboxed()->bool => g_Sandboxed

// Reports whether the process is a smoke run: the real program, bounded by its launcher.
//
// Code driving its own loop instead of [Gui.Application.run](std.gui.html#Gui_Application_run)
// asks this to know when to stop.
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

// Returns the corpus root, or an empty string when the run was granted none.
func corpusRoot()->string => g_CorpusRoot.toString()

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

// Reports whether `path` is inside the granted corpus. Answers false when there is none.
func isInsideCorpus(path: string)->bool => isInsideDirectory(g_CorpusRoot.toString(), path)

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

// Fails when `path` would be written outside the sandbox and outside the granted corpus.
//
// Every operation in [[Core.File]] and [[Core.Directory]] that creates, modifies or removes
// something calls this first. Outside a sandbox it is a single boolean test.
internal func guardWrite(path: string) fail
{
    if !g_Sandboxed do
        return
    if isInsideSandbox(path) or isInsideCorpus(path) do
        return
    fail SandboxError{"refusing to write outside the sandbox", path: absolutePath(path).toString()}
}
