#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func createSandboxTestDirectoryLink(link, target: string)->bool
{
    #static if #os == Swag.TargetOs.Linux
    {
        let nativeLink   = String.from(link)
        let nativeTarget = String.from(target)
        return Linux.symlinkat(nativeTarget.storage(), Linux.AT_FDCWD, nativeLink.storage()) == 0
    }
    else
    {
        let fontsDir   = Env.realSpecialDirectory(.Font)
        let windowsDir = Path.directoryName(fontsDir.toString())
        let shell      = Path.combine(windowsDir, "System32", "cmd.exe")
        let arguments  = Format.toString("/c mklink /J \"%\" \"%\"", link, target)
        let process    = catch Env.runProcess(Env.StartInfo{fileName: shell.toString(), nativeArguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe}) { return false }
        return process.exitCode() == 0
    }
}

// Containment, not prefix matching. 'sandboxed' starts with 'sandbox' but is not inside it,
// and that difference is the whole value of the check.
#test
{
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox"))
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/a.txt"))
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/deep/a.txt"))

    Swag.require(not Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandboxed/a.txt"))
    Swag.require(not Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp"))
    Swag.require(not Env.isInsideDirectory("C:/tmp/sandbox", "C:/other/a.txt"))
    Swag.require(not Env.isInsideDirectory("C:/tmp/sandbox", "D:/tmp/sandbox/a.txt"))
}

// Windows treats separator style and case as aliases; Linux preserves both distinctions.
#test
{
    #static if WINDOWS
    {
        Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:\\tmp\\sandbox\\a.txt"))
        Swag.require(Env.isInsideDirectory("C:\\tmp\\sandbox", "C:/tmp/sandbox/a.txt"))
        Swag.require(Env.isInsideDirectory("C:/TMP/Sandbox", "c:/tmp/sandbox/a.txt"))
    }
    else
    {
        Swag.require(not Env.isInsideDirectory("/tmp/sandbox", "/tmp/sandbox\\a.txt"))
        Swag.require(not Env.isInsideDirectory("/tmp/Sandbox", "/tmp/sandbox/a.txt"))
    }

    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/./a.txt"))
    Swag.require(not Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/../a.txt"))
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/.. /a.txt") == not WINDOWS)
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/name. /a.txt") == not WINDOWS)
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/NUL.txt") == not WINDOWS)
    Swag.require(Env.isInsideDirectory("C:/tmp/sandbox", "C:/tmp/sandbox/COM1.log") == not WINDOWS)
}

// An empty root contains nothing. Answering true would turn a failure to configure the
// sandbox into a wide-open one.
#test
{
    Swag.require(not Env.isInsideDirectory("", "C:/tmp/a.txt"))
}

// The guard is transparent when no sandbox is armed, and refuses everything outside it when
// one is. 'swc test' arms it, so both halves are exercised depending on how this runs.
#test
{
    if not Env.isSandboxed()
    {
        expect Env.guardWrite("C:/tmp/anywhere.txt")
        Swag.require(Env.isInsideSandbox("C:/tmp/anywhere.txt"))
        return
    }

    let root = Env.sandboxRoot()
    Swag.require(root.count != 0)

    let inside = Path.combine(root, "guarded.txt")
    expect Env.guardWrite(inside.toString())

    var errOutcome: Swag.Error
    catch Env.guardWrite("C:/Windows/System32/nope.txt") as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(not Env.isInsideSandbox("C:/Windows/System32/nope.txt"))
}

// The corpus is the one place outside the sandbox a run may write. 'swc test' grants the module
// it is testing, so the sources this file lives in accept a write while the machine still does not.
#test
{
    if not Env.isSandboxed() do
        return

    let corpus = Env.corpusRoot()
    Swag.require(corpus.count != 0)
    Swag.require(Env.isInsideCorpus(corpus))

    let inside = Path.combine(corpus, "corpus-write.txt")
    expect Env.guardWrite(inside.toString())

    Swag.require(not Env.isInsideCorpus("C:/Windows/System32/nope.txt"))
    var errOutcome: Swag.Error
    catch Env.guardWrite("C:/Windows/System32/nope.txt") as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// An empty root is a launcher mistake, and answering it with a grant would turn a corpus that
// was never configured into one that contains everything.
#test
{
    var errOutcome: Swag.Error
    catch Env.grantCorpus("") as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// Granting the same root again is the no-op a hook running twice needs; a different one is
// refused, because code may already hold paths derived from the first.
#test
{
    let corpus = Env.corpusRoot()
    if corpus.count == 0 do
        return

    expect Env.grantCorpus(corpus)

    var errOutcome: Swag.Error
    catch Env.grantCorpus(Env.getSpecialDirectory(.Temp).toString()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(Env.corpusRoot() == corpus)
}

// Every well-known directory answers inside the sandbox, and two different kinds stay
// distinct so an application that separates documents from settings still sees two places.
#test
{
    if not Env.isSandboxed() do
        return

    let docs    = Env.getSpecialDirectory(.UserDocuments)
    let appData = Env.getSpecialDirectory(.UserAppData)
    let tempDir = Env.getSpecialDirectory(.Temp)
    let root    = Env.sandboxRoot()

    Swag.require(Env.isInsideDirectory(root, docs.toString()))
    Swag.require(Env.isInsideDirectory(root, appData.toString()))
    Swag.require(Env.isInsideDirectory(root, tempDir.toString()))
    Swag.require(docs != appData)
    Swag.require(Directory.exists(docs))
}

// The private root is computed from the machine's temporary directory, never from the sandbox's
// stand-in for it. The arming hook runs again in a process that also executes code at compile
// time, and a root recomputed through the redirection nests under the one already armed, which
// is rejected as a change of root and kills the whole run.
#test
{
    if not Env.isSandboxed() do
        return

    let standIn = Env.getSpecialDirectory(.Temp)
    let root    = Env.defaultSandboxRoot()
    Swag.require(not Env.isInsideDirectory(standIn.toString(), root.toString()))
}

// A leftover root is removed whole, files and sub-directories included, and a name nothing owns
// is accepted silently. The operating system reuses process ids, so both states are normal when
// the sandbox adopts its default name.
#test
{
    if not Env.isSandboxed() do
        return

    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "leftover-run")
    let nested = Path.combine(root.toString(), "nested")
    expect Directory.create(root.toString())
    expect Directory.create(nested.toString())

    let payload: [4] u8 = [1, 2, 3, 4]
    let stale = Path.combine(nested.toString(), "stale.bin")
    discard expect File.writeAllBytes(stale.toString(), payload)

    expect Env.clearLeftoverDefaultRoot(root.toString())
    Swag.require(not Directory.exists(root.toString()))

    expect Env.clearLeftoverDefaultRoot(root.toString())
}

// Windows sharing can prevent clearing a held file; POSIX unlink leaves the existing
// descriptor usable while removing the name and its containing directory.
#test
{
    if not Env.isSandboxed() do
        return

    let root = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "leftover-held")
    expect Directory.create(root.toString())

    let heldPath = Path.combine(root.toString(), "held.bin")
    var held     = expect File.open(heldPath.toString(), .Create, .Write, .Read)
    var errOutcome: Swag.Error
    catch Env.clearLeftoverDefaultRoot(root.toString()) as errOutcome
    let err = errOutcome.value()
    #static if WINDOWS do
        Swag.require(err != null)
    else
    {
        Swag.require(err == null and not Directory.exists(root.toString()))
        expect held.writeAll([17'u8, 19])
        let retainedSize = expect held.size()
        Swag.require(retainedSize == 2)
    }

    held.close()
    expect Env.clearLeftoverDefaultRoot(root.toString())
    Swag.require(not Directory.exists(root.toString()))
}

// A fallback sibling stays beside the name it replaces — same parent, the plain name as its
// prefix — so the leftover and its adopter both stay matchable to the process id that owns them.
#test
{
    let base = Env.defaultSandboxRoot()
    let alt  = Env.defaultSandboxRoot(2)

    var expected = String.from(base.toString())
    expected += "-2"
    Swag.require(alt.toString() == expected.toString())
}

// A real write lands in the sandbox and a real write outside is refused, through the public
// file API rather than the guard alone.
#test
{
    if not Env.isSandboxed() do
        return

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "sandbox-write.txt")
    defer discard catch File.delete(path.toString())

    let payload: [4] u8 = [1, 2, 3, 4]
    discard expect File.writeAllBytes(path.toString(), payload)
    Swag.require(File.exists(path.toString()))

    var errOutcome: Swag.Error
    discard catch File.writeAllBytes("C:/Windows/swag-sandbox-escape.txt", payload) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require(not File.exists("C:/Windows/swag-sandbox-escape.txt"))
}

// A directory link cannot redirect an allowed sandbox write into the granted corpus.
#test
{
    if not Env.isSandboxed() do
        return

    let holding    = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("sandbox-reparse-%", Guid64.random()))
    let target     = Path.combine(Env.corpusRoot(), Format.toString("sandbox-reparse-target-%", Guid64.random()))
    let link       = Path.combine(holding.toString(), "linked")
    let targetFile = Path.combine(target.toString(), "keep.txt")
    expect Directory.create(holding.toString())
    expect Directory.create(target.toString())
    defer discard catch Directory.delete(holding.toString(), recurse: true)
    defer discard catch Directory.delete(target.toString(), recurse: true)
    discard expect File.writeAllText(targetFile.toString(), "keep")

    let linked = createSandboxTestDirectoryLink(link.toString(), target.toString())
    Swag.require(linked)

    var errorOutcome: Swag.Error
    discard catch File.writeAllText(Path.combine(link.toString(), "escaped.txt"), "escape") as errorOutcome
    Swag.require(errorOutcome.value() is Errors.SandboxError)
    Swag.require(expect File.readAllText(targetFile.toString()) == "keep")

    // Removing the link itself is safe; traversing it to remove a child is still refused.
    let targetChild = Path.combine(target.toString(), "child")
    expect Directory.create(targetChild.toString())
    var deleteOutcome: Swag.Error
    catch Directory.delete(Path.combine(link.toString(), "child"), recurse: true) as deleteOutcome
    Swag.require(deleteOutcome.value() is Errors.SandboxError)
    Swag.require(Directory.exists(targetChild.toString()))

    expect Directory.delete(link.toString(), recurse: true)
    Swag.require(not Directory.exists(link.toString()))
    Swag.require(Directory.exists(targetChild.toString()))
    Swag.require(expect File.readAllText(targetFile.toString()) == "keep")
}

#test
{
    let arguments: [?] string = ["program", "swag.sandbox.corpus=/data", "swag.sandbox-extra", "swag.sandbox=/tmp/space name"]
    let parsed = Env.findRunArgumentIn(arguments, "swag.sandbox")
    Swag.require(parsed.found and parsed.value == "/tmp/space name")
    let bare = Env.findRunArgumentIn(["program", "swag.sandbox"], "swag.sandbox")
    Swag.require(bare.found and bare.value.isEmpty())
    let absent = Env.findRunArgumentIn(["swag.sandbox.corpus=/data", "swag.sandbox-extra"], "swag.sandbox")
    Swag.require(not absent.found)
    Swag.require(not Env.isInsideDirectory("/tmp\0ignored", "/tmp/file"))
    Swag.require(not Env.isInsideDirectory("/tmp", ""))
}
