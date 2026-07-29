#global public
#global namespace Testing

using Swag, Core

// Compile-time switch that turns golden assertions from *compare* into *record*.
//
// It is driven by the 'Std.Pixel.UpdateGoldens' compiler tag, so it applies to both the JIT and
// the native pass of a test run:
//
// ```
// tools\std.bat dm test -m pixel --tag Std.Pixel.UpdateGoldens --rebuild
// ```
//
// The switch is compiled into this module, so recording the goldens of a *dependent* module needs
// this module rebuilt with the tag; a tag change alone does not invalidate the module cache, hence
// '--rebuild'.
//
// Every golden touched by the run is then rewritten from the current output instead of being
// compared, and the assertion always succeeds. Review the resulting diff before committing it:
// recording a golden accepts whatever the code currently produces, including a regression.
const UpdateGoldens = #hastag("Std.Pixel.UpdateGoldens")

// Compares the display list recorded by 'painter' against the golden named 'name'.
//
// The painter is serialized with [[Testing.dumpPainter]], so this asserts on the *commands* a
// drawing emits, not on the pixels it would produce: it needs no GPU and no window, and its
// result is identical on every machine.
//
// Goldens live in a 'goldens' folder next to the calling source file, one '.txt' file per name.
// 'name' may contain '/' to group goldens in sub-folders. A missing golden fails the assertion
// instead of being created silently; record it with [[Testing.UpdateGoldens]].
//
// On mismatch the produced text is written next to the golden as '<name>.actual.txt' and a
// line-level report is printed to the console before the assertion fails.
func assertGolden(painter: const *Painter, name: string, level = DumpLevel.Full, loc = #callerlocation)
{
    let dump = dumpPainter(painter, level)
    assertGoldenText(dump.toString(), name, loc)
}

// Compares arbitrary text against the golden named 'name'.
//
// Behaves exactly like [[Testing.assertGolden]] but takes the snapshot text directly, for callers
// that build their own normalized representation. Both sides are compared with end of lines
// normalized to '\n', so a CRLF checkout never changes the outcome.
func assertGoldenText(text: string, name: string, loc = #callerlocation)
{
    let path = goldenPath(name, loc)

    #static if UpdateGoldens
    {
        writeText(path.toString(), text)
        Console.println("[golden] recorded ", name)
        return
    }

    if !File.exists(path)
    {
        let actual = actualPath(path.toString())
        writeText(actual.toString(), text)
        Console.println("[golden] MISSING ", name)
        Console.println("         expected : ", path)
        Console.println("         produced : ", actual)
        Console.println("         record it with --tag Std.Pixel.UpdateGoldens")
        @assert(false)
        return
    }

    let expected = catch File.readAllText(path.toString(), .Utf8, normalizeEol: true) as errRead
    if errRead != null
    {
        Console.println("[golden] UNREADABLE ", path)
        @assert(false)
        return
    }

    if expected.toString() == text do
        return

    let actual = actualPath(path.toString())
    writeText(actual.toString(), text)
    reportDiff(name, path.toString(), actual.toString(), expected.toString(), text)
    @assert(false)
}

private
{
    // Goldens sit in a 'goldens' folder beside the test source file, so a test and its snapshots
    // move together and a module owns its own corpus.
    func goldenPath(name: string, loc: Swag.SourceCodeLocation)->String
    {
        let dir    = Path.getDirectoryName(loc.fileName)
        let folder = Path.combine(dir, "goldens")

        var file = String.from(name)
        file += ".txt"
        return Path.combine(folder.toString(), file.toString())
    }

    func actualPath(path: string)->String
    {
        var result = String.from(path)
        result.removeBack(4)     // ".txt"
        result += ".actual.txt"
        return result
    }

    // Writes UTF-8 bytes with the '\n' separators the text already carries. Going through
    // 'writeAllBytes' rather than a text writer guarantees the stored file keeps single '\n',
    // whatever the platform default is.
    func writeText(path: string, text: string)
    {
        let dir = Path.getDirectoryName(path)
        if dir != null and !Directory.exists(dir)
        {
            catch Directory.create(dir) as errDir
            if errDir != null
            {
                Console.println("[golden] cannot create ", dir)
                return
            }
        }

        discard catch File.writeAllBytes(path, @mkslice(@dataof(text), @countof(text))) as errWrite
        if errWrite != null do
            Console.println("[golden] cannot write ", path)
    }

    func splitLines(text: string)->Array'String
    {
        var result: retval
        var cur:    String

        for [i] in @countof(text)
        {
            if text[i] == '\n'u8
            {
                result.add(cur)
                cur.clear()
            }
            else do
                cur.append(text[i])
        }

        if !cur.isEmpty() do
            result.add(cur)
        return result
    }

    // Prints the first differing line rather than the whole snapshot: a command dump is long, and
    // the first divergence is almost always the regression itself.
    func reportDiff(name: string, goldenFile: string, actualFile: string, expected: string, actual: string)
    {
        let expectedLines = splitLines(expected)
        let actualLines   = splitLines(actual)

        Console.println("[golden] MISMATCH ", name)
        Console.println("         golden : ", goldenFile)
        Console.println("         actual : ", actualFile)
        Console.println("         lines  : ", expectedLines.count, " expected, ", actualLines.count, " produced")

        let common = Math.min(expectedLines.count, actualLines.count)
        for [i] in common
        {
            if expectedLines[i] == actualLines[i] do
                continue

            Console.println("         first difference at line ", i + 1)
            Console.println("           expected | ", expectedLines[i])
            Console.println("           produced | ", actualLines[i])
            return
        }

        if actualLines.count > common
        {
            Console.println("         extra line ", common + 1)
            Console.println("           produced | ", actualLines[common])
        }
        elif expectedLines.count > common
        {
            Console.println("         missing line ", common + 1)
            Console.println("           expected | ", expectedLines[common])
        }
    }
}
