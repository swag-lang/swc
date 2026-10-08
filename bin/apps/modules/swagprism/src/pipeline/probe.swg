#global internal
#global namespace Pipeline

using Core

// Folder the snippet module lives in, which is also the name the compiler reports it under.
private const ProbeModuleName = "prismprobe"

// What one compilation of a snippet left behind.
struct Result
{
    text:   String     // What the compiler wrote, including its terminal colors.
    failed: bool       // Whether the compiler stopped before it could print a stage.
}

// Owns the temporary module and artifact directory used by one compilation.
// Separate sessions keep simultaneous builds from sharing source files or outputs.
#[Swag.NoCopy]
struct Probe
{
    session: String     // Folder this probe owns and removes, empty until it is opened.
    root:    String     // Module folder inside it, which is the name the compiler reports.
}

impl Probe
{
    mtd opDrop() { .close() }

    // Removes the temporary module, leaving the probe ready to be opened again.
    mtd close()
    {
        if .session.isEmpty() do
            return
        discard catch Directory.delete(.session, recurse: true)
        .session.clear()
        .root.clear()
    }

    // Creates the temporary module the snippet is compiled in, unless it already exists.
    mtd open() fail
    {
        if not .root.isEmpty() do
            return

        // Every viewer shares this parent, and any of them may be the one that creates it.
        let owned = Path.combine(Env.getSpecialDirectory(.Temp), "swagprism")
        try Directory.create(owned, recurse: true)

        // Claim a directory before writing: concurrent artifacts and application instances must
        // never share mutable sources or outputs.
        var session: String
        for
        {
            session = Path.combine(owned, Guid64.highEntropy().toString())
            catch Directory.create(session) as createError
            if createError == null do
                break

            // Creating the directory claims it. A colliding name belongs to another probe.
            if not Directory.exists(session) do
                fail createError
        }

        // The compiler names the module after its folder, and that name prefixes every function it
        // reports. The session identifier goes in the folder above so the pane says `Prismprobe.dot`
        // rather than pinning the reader's own function under a random string.
        var root = Path.combine(session, ProbeModuleName)
        try Directory.create(Path.combine(root, "src"), recurse: true)

        .session = #move session
        .root    = #move root
    }
}

// How long one compiler run may take before the interface stops waiting for it.
const CompilerTimeoutMs = 60_000'u64

/*
Path of the compiler that builds the snippets.

An explicit `--compiler=<path>` launch argument selects a development compiler before discovery.

A shipped application sits in the directory the compiler was published to, so the compiler beside it
is the one that matches this build. A development build sits several directories under that same
root instead — `bin/apps/.output/<module>/<backend>/<config>/<arch>` — so the search walks up from
the executable rather than looking only next to it, and finds the same compiler either way.

The bare name is the last resort: it leaves the application working wherever the system path
resolves the compiler, and it is what the reader sees named when nothing does.
*/
func compilerPath()->String
{
    const CompilerName = "swc.exe"

    let requested = compilerArgument("--compiler=")
    if requested.count do
        return requested

    var folder = String.from(Path.directoryName(Env.executablePath()))
    while not folder.isEmpty()
    {
        let candidate = Path.combine(folder, CompilerName)
        if File.exists(candidate) do
            return candidate

        let parent = Path.directoryName(folder)
        if parent == null or Path.equals(parent, folder) do
            break
        folder = parent
    }

    return CompilerName
}

/*
Number of compiler workers one snippet compilation asks for.

The compiler creates exactly the workers it is given and never clamps the count to the machine, so
the number has to be computed here. Two facts bound it. The application is drawing while the
compiler runs, so it keeps a processor for itself. And the compiler stops paying for workers long
before a large machine runs out: measured on a twenty-two processor machine, one snippet takes
324 ms with six workers, 264 ms with twelve, and 266 ms with twenty-two — the last for a quarter
more processor time, which the interface then has to compete with.

The `--compiler-workers=<count>` launch argument can lower this budget for shared-machine runs.
*/
func compilerWorkerCount()->u32
{
    // Where another worker stops buying wall time and only takes processor time from the interface.
    const MaxWorkers = 12'u32

    let available = Hardware.processorCount()
    if available <= 2 do
        return 1
    let requested = catch StrConv.toU32(compilerArgument("--compiler-workers="))
    let limit     = requested != 0 ? Math.min(requested, MaxWorkers) : MaxWorkers
    return Math.min(available - 1, limit)
}

// Explicit launch options let development runs select the compiler and share a worker budget.
private func compilerArgument(prefix: string)->string
{
    for argument in Env.arguments() where Utf8.startsWith(cast(const [..] u8, argument), prefix) do
        return argument[prefix.count to]
    return ""
}

/*
Returns `source` with the attributes that make one function inspectable.

`Swag.PrintMicro` is an attribute rather than a compiler flag, so asking for a stage means writing
it into the source. Swag Prism inspects the first function the snippet declares: that rule is
simple enough for a reader to hold, and it puts the choice where they can see it, since moving a
function to the top is how they change what is inspected.

A snippet that declares no function is returned unchanged. It will compile and print nothing, which
is the honest outcome — there is nothing to show.
*/
func inspectedSource(source: string, stage: string)->String
{
    let cut = firstFunctionOffset(source)

    var result: retval
    if cut == Swag.U64.Max
    {
        result.append(source)
        return result
    }

    result.append(source[until cut])
    result.appendFormat("#[Swag.PrintMicro(\"%\")]\n", stage)
    result.append(source[cut to])
    return result
}

// Offset of the first top-level `func` declaration in `source`, or `U64.Max` when it has none.
//
// The scan only accepts a `func` that starts its own line at column zero, which is what keeps a
// nested function, a method, and the word inside a comment or a string from being taken for the
// declaration the reader meant.
private func firstFunctionOffset(source: string)->u64
{
    const Marker = "func "

    let bytes = cast(const [..] u8, source)
    var start = 0'u64
    while start < bytes.count
    {
        var end = start
        while end < bytes.count and bytes[end] != '\n' do
            end += 1

        if end - start > Marker.count and Utf8.startsWith(bytes[start until end], Marker) do
            return start

        start = end + 1
    }

    return Swag.U64.Max
}

/*
Writes `content` to `path`, unless the file already holds exactly that text.

The compiler answers a module's setup from its cache only while the setup file has the modification
time and the size it recorded, so rewriting an unchanged `module.swg` on every keystroke throws that
cache away for nothing. A file that cannot be read back is written.
*/
func writeIfChanged(path: string, content: string) fail
{
    let existing = catch File.readAllText(path) as readError
    if readError == null and existing == content do
        return
    discard try File.writeAllBytes(path, cast(const [..] u8, content))
}

// Always reap an owned process before dropping its pipes or temporary files.
func retireProcess(process: *Env.Process)
{
    if not (catch process.tryWaitForExit(0'ms))
    {
        discard catch process.kill()
        discard catch process.waitForExit()
    }
}
