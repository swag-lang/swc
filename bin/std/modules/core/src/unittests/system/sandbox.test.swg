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
