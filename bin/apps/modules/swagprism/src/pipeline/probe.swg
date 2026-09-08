#global internal
#global namespace Pipeline

using Core

// Folder the snippet module lives in, which is also the name the compiler reports it under.
private const ProbeModuleName = "prismprobe"

/*
The module setup the probe compiles the snippet in.

The snippet is the whole of a module of its own, so nothing the user writes has to know it is being
inspected, and a snippet that does not compile stops nothing but its own build.

A static library is what the snippet is built as. Code is generated for every function it declares,
which is what the pane reads, and nothing has to be linked or given a `#main` — so a snippet is one
loose function rather than a program, which is how a reader wants to write one.
*/
private const ProbeModuleSource = """\
    #run
    {
        with let cfg = Swag.compiler().getBuildCfg()!
        {
            .backendKind = .StaticLibrary
        }
    }
    """

/*
The configuration the snippet is built in.

Swag Prism shows the code that would ship. A development build inserts the bounds checks and the
overflow guards a released one leaves out, and a pane full of calls to `Swag.safetyPanic` answers a
question nobody asked about a backend they came to judge. The `Swag.Optimize` attribute still lowers
one function to O0 inside this configuration, which is how the pane offers unoptimized code.
*/
private const ProbeBuildConfig = "release"

// What one compilation of a snippet left behind.
struct Result
{
    public
    {
        text:   String     // What the compiler wrote, with terminal escapes removed.
        failed: bool       // Whether the compiler stopped before it could print a stage.
    }
}

/*
Compiles one snippet on its own and collects what the compiler printed about it.

The snippet is built as a module in a temporary folder by a separate compiler process. That is the
whole point of the type: a snippet that does not compile, loops forever, or stops the compiler
outright must cost the reader the output pane and never the text they were writing.

The folder is created once and reused for every compilation, because the compiler keys its cache on
the module and a folder that moves between runs throws that cache away on every keystroke.
*/
#[Swag.NoCopy]
struct Probe
{
    session: String     // Folder this probe owns and removes, empty until it is opened.
    root:    String     // Module folder inside it, which is the name the compiler reports.
}

impl Probe
{
    mtd opDrop()
    {
        .close()
    }

    // Removes the temporary module, leaving the probe ready to be opened again.
    mtd close()
    {
        if .session.isEmpty() do
            return
        discard catch Directory.delete(.session.toString(), recurse: true)
        .session.clear()
        .root.clear()
    }

    // Creates the temporary module the snippet is compiled in, unless it already exists.
    mtd open() fail
    {
        if !.root.isEmpty() do
            return

        // Each level is created in turn because `Directory.create` makes one directory and not the
        // path leading to it, and none of these is there on a first run.
        let owned = Path.combine(Env.getSpecialDirectory(.Temp), "swagprism")
        if !Directory.exists(owned) do
            try Directory.create(owned.toString())

        // One session folder per probe rather than one per compilation: the compiler cache lives
        // with the module, and a folder that moves between runs throws that cache away on every
        // keystroke — while a second instance of the application must not build into the first
        // one's.
        var session = Path.combine(owned, Format.toString("%", Guid64.random()))
        try Directory.create(session.toString())

        // The compiler names the module after its folder, and that name prefixes every function it
        // reports. The session identifier goes in the folder above so the pane says `Prismprobe.dot`
        // rather than pinning the reader's own function under a random string.
        var root = Path.combine(session, ProbeModuleName)
        try Directory.create(root.toString())
        try Directory.create(Path.combine(root, "src").toString())

        let moduleFile = Path.combine(root, "module.swg")
        discard try File.writeAllBytes(moduleFile.toString(), cast(const [..] u8) ProbeModuleSource)

        .session = #move session
        .root    = #move root
    }

    // Compiles `source` and returns what the compiler printed about `stage`.
    mtd compile(source: string, stage: string, optimize: bool)->Result fail
    {
        try .open()

        let sourceFile = Path.combine(.root, "src", "probe.swg")
        let inspected  = inspectedSource(source, stage, optimize)
        discard try File.writeAllBytes(sourceFile.toString(), cast(const [..] u8) inspected.toString())

        let compiler  = compilerPath()
        let arguments = Format.toString("build --build-cfg % --module \"%\"", ProbeBuildConfig, .root)

        let info = Env.StartInfo{fileName: compiler.toString(), arguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe}

        var process = try Env.runProcess(info)

        var result: retval
        result.text   = withoutTerminalEscapes(process.standardOutput())
        result.failed = process.exitCode() != 0
        if result.failed do
            result.text.append(withoutTerminalEscapes(process.standardError()).toString())
        return result
    }
}

/*
Path of the compiler that builds the snippets.

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

    var folder = String.from(Path.directoryName(Env.executablePath()))
    while !folder.isEmpty()
    {
        let candidate = Path.combine(folder, CompilerName)
        if File.exists(candidate.toString()) do
            return candidate

        let parent = Path.directoryName(folder.toString())
        if parent == null or Path.equals(parent!, folder.toString()) do
            break
        folder = String.from(parent)
    }

    return String.from(CompilerName)
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
func inspectedSource(source: string, stage: string, optimize: bool)->String
{
    let cut = firstFunctionOffset(source)

    var result: retval
    if cut == Swag.U64.Max
    {
        result.append(source)
        return result
    }

    result.append(source[0 until cut])
    result.appendFormat("#[Swag.PrintMicro(\"%\"), Swag.Optimize(%)]\n", stage, optimize ? "true" : "false")
    result.append(source[cut until source.count])
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

    let bytes = cast(const [..] u8) source
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
Returns `text` without the escape sequences a terminal would have consumed.

The compiler colors what it prints for a console, and a pipe receives those sequences as text. The
interface colors the output itself from the structure it parses, so the sequences are removed
rather than translated here.
*/
func withoutTerminalEscapes(text: string)->String
{
    const Escape = 27'u8

    let bytes = cast(const [..] u8) text

    var result: retval
    var index = 0'u64
    while index < bytes.count
    {
        if bytes[index] != Escape
        {
            result.append(bytes[index])
            index += 1
            continue
        }

        // A control sequence runs from the introducer to the first byte in the final range, which
        // is where every sequence the compiler emits ends whether or not this build knows it.
        index += 1
        if index < bytes.count and bytes[index] == '[' do
            index += 1
        while index < bytes.count and (bytes[index] < '@' or bytes[index] > '~') do
            index += 1
        if index < bytes.count do
            index += 1
    }

    return result
}
