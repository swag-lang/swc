#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Containment, not prefix matching. 'sandboxed' starts with 'sandbox' but is not inside it,
// and that difference is the whole value of the check.
#test
{
    @assert(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox"))
    @assert(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/a.txt"))
    @assert(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/deep/a.txt"))

    @assert(!Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandboxed/a.txt"))
    @assert(!Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp"))
    @assert(!Env.isInsideDirectory("C:/tmp/sandbox", "C:/other/a.txt"))
    @assert(!Env.isInsideDirectory("C:/tmp/sandbox", "D:/tmp/sandbox/a.txt"))
}

// Separator style and case are normalized away: a caller must not be able to escape by
// spelling the same location differently.
#test
{
    @assert(Env.isInsideDirectory("C:/tmp/sandbox", "C:\\tmp\\sandbox\\a.txt"))
    @assert(Env.isInsideDirectory("C:\\tmp\\sandbox", "C:/tmp/sandbox/a.txt"))
    @assert(Env.isInsideDirectory("C:/TMP/Sandbox", "c:/tmp/sandbox/a.txt"))
    @assert(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/./a.txt"))
    @assert(!Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/../a.txt"))
}

// An empty root contains nothing. Answering true would turn a failure to configure the
// sandbox into a wide-open one.
#test
{
    @assert(!Env.isInsideDirectory("", "C:/tmp/a.txt"))
}

// The guard is transparent when no sandbox is armed, and refuses everything outside it when
// one is. 'swc test' arms it, so both halves are exercised depending on how this runs.
#test
{
    if !Env.isSandboxed()
    {
        expect Env.guardWrite("C:/tmp/anywhere.txt")
        @assert(Env.isInsideSandbox("C:/tmp/anywhere.txt"))
        return
    }

    let root = Env.sandboxRoot()
    @assert(@countof(root) != 0)

    let inside = Path.combine(root, "guarded.txt")
    expect Env.guardWrite(inside.toString())

    catch Env.guardWrite("C:/Windows/System32/nope.txt") as err
    @assert(err != null)
    @assert(!Env.isInsideSandbox("C:/Windows/System32/nope.txt"))
}

// The corpus is the one place outside the sandbox a run may write. 'swc test' grants the module
// it is testing, so the sources this file lives in accept a write while the machine still does not.
#test
{
    if !Env.isSandboxed() do
        return

    let corpus = Env.corpusRoot()
    @assert(@countof(corpus) != 0)
    @assert(Env.isInsideCorpus(corpus))

    let inside = Path.combine(corpus, "corpus-write.txt")
    expect Env.guardWrite(inside.toString())

    @assert(!Env.isInsideCorpus("C:/Windows/System32/nope.txt"))
    catch Env.guardWrite("C:/Windows/System32/nope.txt") as err
    @assert(err != null)
}

// An empty root is a launcher mistake, and answering it with a grant would turn a corpus that
// was never configured into one that contains everything.
#test
{
    catch Env.grantCorpus("") as err
    @assert(err != null)
}

// Granting the same root again is the no-op a hook running twice needs; a different one is
// refused, because code may already hold paths derived from the first.
#test
{
    let corpus = Env.corpusRoot()
    if @countof(corpus) == 0 do
        return

    expect Env.grantCorpus(corpus)

    catch Env.grantCorpus(Env.getSpecialDirectory(.Temp).toString()) as err
    @assert(err != null)
    @assert(Env.corpusRoot() == corpus)
}

// Every well-known directory answers inside the sandbox, and two different kinds stay
// distinct so an application that separates documents from settings still sees two places.
#test
{
    if !Env.isSandboxed() do
        return

    let docs    = Env.getSpecialDirectory(.UserDocuments)
    let appData = Env.getSpecialDirectory(.UserAppData)
    let tempDir = Env.getSpecialDirectory(.Temp)
    let root    = Env.sandboxRoot()

    @assert(Env.isInsideDirectory(root, docs.toString()))
    @assert(Env.isInsideDirectory(root, appData.toString()))
    @assert(Env.isInsideDirectory(root, tempDir.toString()))
    @assert(docs != appData)
    @assert(Directory.exists(docs))
}

// The private root is computed from the machine's temporary directory, never from the sandbox's
// stand-in for it. The arming hook runs again in a process that also executes code at compile
// time, and a root recomputed through the redirection nests under the one already armed, which
// is rejected as a change of root and kills the whole run.
#test
{
    if !Env.isSandboxed() do
        return

    let standIn = Env.getSpecialDirectory(.Temp)
    let root    = Env.defaultSandboxRoot()
    @assert(!Env.isInsideDirectory(standIn.toString(), root.toString()))
}

// A leftover root is removed whole, files and sub-directories included, and a name nothing owns
// is accepted silently. The operating system reuses process ids, so both states are normal when
// the sandbox adopts its default name.
#test
{
    if !Env.isSandboxed() do
        return

    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "leftover-run")
    let nested = Path.combine(root.toString(), "nested")
    expect Directory.create(root.toString())
    expect Directory.create(nested.toString())

    let payload: [4] u8 = [1, 2, 3, 4]
    let stale           = Path.combine(nested.toString(), "stale.bin")
    discard expect File.writeAllBytes(stale.toString(), payload)

    expect Env.clearLeftoverDefaultRoot(root.toString())
    @assert(!Directory.exists(root.toString()))

    expect Env.clearLeftoverDefaultRoot(root.toString())
}

// A leftover a third party still holds inside refuses to clear, and reports it rather than
// adopting the root half-emptied; the same clear succeeds once the hold is gone. This is the
// premise behind the arming hook's fallback siblings.
#test
{
    if !Env.isSandboxed() do
        return

    let root = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "leftover-held")
    expect Directory.create(root.toString())

    let heldPath = Path.combine(root.toString(), "held.bin")
    var held     = expect File.open(heldPath.toString(), .Create, .Write, .Read)
    catch Env.clearLeftoverDefaultRoot(root.toString()) as err
    @assert(err != null)

    held.close()
    expect Env.clearLeftoverDefaultRoot(root.toString())
    @assert(!Directory.exists(root.toString()))
}

// A fallback sibling stays beside the name it replaces — same parent, the plain name as its
// prefix — so the leftover and its adopter both stay matchable to the process id that owns them.
#test
{
    let base = Env.defaultSandboxRoot()
    let alt  = Env.defaultSandboxRoot(2)

    var expected = String.from(base.toString())
    expected += "-2"
    @assert(alt.toString() == expected.toString())
}

// A real write lands in the sandbox and a real write outside is refused, through the public
// file API rather than the guard alone.
#test
{
    if !Env.isSandboxed() do
        return

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "sandbox-write.txt")
    defer discard catch File.delete(path.toString())

    let payload: [4] u8 = [1, 2, 3, 4]
    discard expect File.writeAllBytes(path.toString(), payload)
    @assert(File.exists(path.toString()))

    let refused = catch File.writeAllBytes("C:/Windows/swag-sandbox-escape.txt", payload) as err
    discard refused
    @assert(err != null)
    @assert(!File.exists("C:/Windows/swag-sandbox-escape.txt"))
}
