#global public
#global namespace Testing

using Swag, Core

// Configures tolerated differences when comparing a rendered image with its PNG golden.
struct ImageGoldenOptions
{
    maxChannelDelta:    u8      // Maximum absolute difference accepted for each ARGB channel.
    maxDifferentPixels: u64     // Maximum number of pixels allowed outside the channel tolerance.
}

// Compares the display list recorded by 'painter' against the golden named 'name'.
//
// The painter is serialized with [[Testing.dumpPainter]], so this asserts on the *commands* a
// drawing emits, not on the pixels it would produce: it needs no GPU and no window, and its
// result is identical on every machine.
//
// Goldens live in a 'goldens' folder next to the calling source file, one '.txt' file per name.
// 'name' may contain '/' to group goldens in sub-folders.
//
// There is no recording mode and no flag to pass. A name with no golden yet writes one and passes,
// so a new test starts by producing its reference; the file then shows up as untracked, which is
// where it gets reviewed and committed. A name whose golden no longer matches writes the produced
// text next to it as '<name>.actual.txt', prints the first differing line, and fails. Accepting
// the new output is therefore a copy, which 'tools\accept-test-goldens.bat' does in bulk.
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
    let path = goldenPath(name, ".txt", loc)

    // No golden yet: write one and let the test pass. It is loud on purpose -- an untracked file
    // appearing in the working tree is what turns a mistyped name into something visible rather
    // than a test that silently asserts nothing forever.
    if !File.exists(path)
    {
        writeText(path.toString(), text)
        Console.println("[golden] created ", name, " -- review it before committing")
        Console.println("         ", path)
        return
    }

    let expected = catch File.readAllText(path.toString(), .Utf8, normalizeEol: true) as errRead
    if errRead != null
    {
        Console.println("[golden] cannot read ", path)
        @assert(false)
        return
    }

    if expected.toString() == text do
        return

    let actual = actualPath(path.toString(), ".txt")
    writeText(actual.toString(), text)
    reportDiff(name, path.toString(), actual.toString(), expected.toString(), text)
    @assert(false)
}

// Compares owned pixels against the PNG golden named `name`.
//
// Goldens live beside the calling test under `goldens/<name>.png`. A missing golden is created
// and passes, like [[Testing.assertGolden]]. A mismatch writes `<name>.actual.png`, reports its
// first differing pixel, and fails. [[Testing.ImageGoldenOptions]] can tolerate bounded codec or
// raster differences; both limits default to exact comparison.
func assertImageGolden(image: const *Image, name: string, options: ImageGoldenOptions = {}, loc = #callerlocation)
{
    Debug.assert(image != null and image.isValid(), "image golden needs allocated pixels")
    let path = goldenPath(name, ".png", loc)

    if !File.exists(path)
    {
        discard catch image.save(path.toString()) as errWrite
        if errWrite != null
        {
            Console.println("[golden] cannot create ", path)
            @assert(false)
            return
        }

        Console.println("[golden] created ", name, " -- review it before committing")
        Console.println("         ", path)
        return
    }

    let expected = catch Image.load(path.toString()) as errRead
    if errRead != null
    {
        Console.println("[golden] cannot read ", path)
        @assert(false)
        return
    }

    var differentPixels: u64
    var firstX, firstY: s32
    var firstExpected, firstActual: Color
    var foundFirst: bool
    let sameSize = expected.width == image.width and expected.height == image.height
    if sameSize
    {
        for var y: s32; y < image.height; y += 1
        {
            for var x: s32; x < image.width; x += 1
            {
                let expectedColor = expected.pixelColor(x, y)
                let actualColor   = image.pixelColor(x, y)
                let delta = Math.max(Math.abs(cast(s32) expectedColor.a - actualColor.a),
                                     Math.max(Math.abs(cast(s32) expectedColor.r - actualColor.r),
                                              Math.max(Math.abs(cast(s32) expectedColor.g - actualColor.g),
                                                       Math.abs(cast(s32) expectedColor.b - actualColor.b))))
                if delta <= options.maxChannelDelta do
                    continue

                differentPixels += 1
                if !foundFirst
                {
                    foundFirst   = true
                    firstX       = x
                    firstY       = y
                    firstExpected = expectedColor
                    firstActual   = actualColor
                }
            }
        }

        if differentPixels <= options.maxDifferentPixels do
            return
    }

    let actual = actualPath(path.toString(), ".png")
    discard catch image.save(actual.toString()) as errWrite
    if errWrite != null do
        Console.println("[golden] cannot write ", actual)

    Console.println("[golden] pixels differ for ", name)
    Console.println("         golden : ", path)
    Console.println("         actual : ", actual)
    if !sameSize
    {
        Console.println("         size   : ", expected.width, "x", expected.height,
                        " expected, ", image.width, "x", image.height, " produced")
    }
    elif foundFirst
    {
        Console.println("         pixels : ", differentPixels, " outside tolerance")
        Console.println("         first  : (", firstX, ", ", firstY, ") expected ",
                        firstExpected.argb, ", produced ", firstActual.argb)
    }
    @assert(false)
}

private
{
    // Goldens sit in a 'goldens' folder beside the test source file, so a test and its snapshots
    // move together and a module owns its own corpus.
    func goldenPath(name, extension: string, loc: Swag.SourceCodeLocation)->String
    {
        let dir    = Path.directoryName(loc.fileName)
        let folder = Path.combine(dir, "goldens")

        var file = String.from(name)
        file += extension
        return Path.combine(folder.toString(), file.toString())
    }

    func actualPath(path, extension: string)->String
    {
        var result = String.from(path)
        result.removeBack(@countof(extension))
        result += ".actual"
        result += extension
        return result
    }

    // Writes UTF-8 bytes with the '\n' separators the text already carries. Going through
    // 'writeAllBytes' rather than a text writer guarantees the stored file keeps single '\n',
    // whatever the platform default is.
    func writeText(path: string, text: string)
    {
        let dir = Path.directoryName(path)
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

        Console.println("[golden] text differs for ", name)
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
