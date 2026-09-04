#global namespace Tool

using Core

/*
The third-party attribution contract, whose two halves both fail quietly.

A file derived from third-party work carries `@NOTICE` beside the code, naming the heading that
holds the attribution; once that heading moves or disappears, the citation still reads like one.
And `bin/THIRDPARTY.md` indexes the notices kept closer to the files they cover; a scoped notice
nobody adds to it is invisible until someone walks the tree by hand.
*/

// The roots that hold shipped sources. Everything else under `bin/` is a workspace cache, which
// carries copies of a notice that are not the tracked one.
private const NoticeRoots = [
    "bin/runtime",
    "bin/std/modules",
    "bin/apps/modules",
    "bin/examples/modules",
    "bin/examples/scripts",
    "bin/reference/modules"]

// The metadata key a derived file carries beside its code.
private const NoticeMarker = "@NOTICE:"

// Checks both halves before every repository test campaign.
public func auditNotices(context: *Context)->s32 fail
{
    let indexFile = Path.combine(context.root.toString(), "bin/THIRDPARTY.md")
    let index     = try File.readAllText(indexFile.toString())

    var errors: u32
    for root in NoticeRoots
    {
        let directory = Path.combine(context.root.toString(), root)
        if !Directory.exists(directory.toString()) do
            continue
        errors += try auditNoticeIndex(context, directory.toString(), index.toString())
        errors += try auditNoticeReferences(context, directory.toString())
    }

    if errors != 0
    {
        Console.println("error: third-party notice validation found ", errors, errors == 1 ? " problem" : " problems")
        return 1
    }

    return 0
}

// Every notice kept beside the files it covers is named by the index a reader starts from.
private func auditNoticeIndex(context: *Context, directory: string, index: string)->u32 fail
{
    var errors: retval
    let files = try Directory.enumerateFiles(directory, ".md", recurse: true)
    for file in files
    {
        if (Path.fileName(file.fullname.toString()) orelse "") != "THIRDPARTY.md" do
            continue

        let relative = noticeRelativePath(context, file.fullname.toString())
        if Utf8.indexOf(cast(const [..] u8) index, relative.toString()) != Swag.U64.Max do
            continue

        Console.println("error: bin/THIRDPARTY.md does not index ", relative.toString())
        errors += 1
    }

    return errors
}

// The index names a notice by its path under `bin/`, which is where a reader of a shipped tree
// stands.
private func noticeRelativePath(context: *Context, fullname: string)->String
{
    let rootLength = (context.root.toString()).count
    let start      = rootLength < fullname.count and (fullname[rootLength] == '/' or fullname[rootLength] == '\\') ? rootLength + 1 : rootLength
    var result     = String.from(fullname[start until fullname.count])
    result.replace("\\", "/")
    if Utf8.startsWith(cast(const [..] u8) result.toString(), "bin/") do
        result = String.from((result.toString())[4 until (result.toString()).count])
    return result
}

private func auditNoticeReferences(context: *Context, directory: string)->u32 fail
{
    var errors: retval
    for extension in [".swg", ".swgs", ".md"]
    {
        let files = try Directory.enumerateFiles(directory, extension, recurse: true)
        for file in files do
            errors += try auditNoticeFile(context, file.fullname.toString())
    }

    return errors
}

private func auditNoticeFile(context: *Context, fileName: string)->u32 fail
{
    let content = try File.readAllText(fileName)

    var errors:     retval
    var lineNumber: u64

    for line in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        let marker = Utf8.indexOf(cast(const [..] u8) line, NoticeMarker)
        if marker == Swag.U64.Max do
            continue

        let target = Latin1.trim(line[marker + NoticeMarker.count until line.count])
        errors += try auditNoticeTarget(context, fileName, lineNumber, target)
    }

    return errors
}

private func auditNoticeTarget(context: *Context, fileName: string, lineNumber: u64, target: string)->u32 fail
{
    let hash = Utf8.indexOf(cast(const [..] u8) target, "#")
    let path = hash == Swag.U64.Max ? target : target[0 until hash]

    // A notice names its attribution either from the shipped root, as `/bin/THIRDPARTY.md`, or
    // beside the file that cites it.
    var resolved: String
    if path.count != 0 and path[0] == '/'
    {
        resolved = Path.combine(context.root.toString(), path[1 until path.count])
    }
    else
    {
        resolved = Path.combine(Path.directoryName(fileName) orelse "", path)
    }

    Path.normalize(&resolved)

    if !File.exists(resolved.toString())
    {
        Console.println("error: ", fileName, ":", lineNumber, ": notice target '", target, "' is missing")
        return 1
    }

    if hash == Swag.U64.Max do
        return 0

    var anchor = String.from(target[hash + 1 until target.count])
    anchor = anchor.toLower()
    if try hasMarkdownHeading(resolved.toString(), anchor.toString()) do
        return 0

    Console.println("error: ", fileName, ":", lineNumber, ": notice fragment '", anchor.toString(), "' has no matching heading in '", path, "'")
    return 1
}
