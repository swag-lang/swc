#global public
#global namespace Testing

using Swag, Core

// Configures tolerated differences for image-to-image and PNG-golden comparisons.
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
// the new output is therefore a copy, which `swc tools/goldens.swgs` does in bulk.
//
// Both writes land in the module source tree, which a sandboxed run reaches only through the
// corpus 'swc test' grants it. See [[Core.Env.grantCorpus]].
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

// Compares two owned pixel buffers with the same bounded tolerance as image goldens.
//
// `expected` and `actual` must be valid images. Dimensions must match exactly. A channel delta
// at or below [[Pixel.Testing.ImageGoldenOptions.maxChannelDelta]] is accepted; at most
// [[Pixel.Testing.ImageGoldenOptions.maxDifferentPixels]] pixels may exceed it. A failed comparison
// writes `<name>.expected.png` and `<name>.actual.png` beside the calling test.
func assertImagesNear(expected, actual: const *Image, name: string, options: ImageGoldenOptions = {}, loc = #callerlocation)
{
    Debug.assert(expected != null and expected.isValid(), "expected image needs allocated pixels")
    Debug.assert(actual != null and actual.isValid(), "actual image needs allocated pixels")

    let difference = compareImages(expected, actual, options)
    if isWithinTolerance(&difference, options) do
        return

    let expectedPath = goldenPath(name, ".expected.png", loc)
    let actualPath   = goldenPath(name, ".actual.png", loc)
    discard writeImage(expected, expectedPath.toString())
    discard writeImage(actual, actualPath.toString())

    Console.println("[image] pixels differ for ", name)
    Console.println("        expected: ", expectedPath)
    Console.println("        actual  : ", actualPath)
    reportImageDifference(&difference, expected, actual)
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
        if !writeImage(image, path.toString())
        {
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

    let difference = compareImages(&expected, image, options)
    if isWithinTolerance(&difference, options) do
        return

    let actual = actualPath(path.toString(), ".png")
    discard writeImage(image, actual.toString())

    Console.println("[golden] pixels differ for ", name)
    Console.println("         golden : ", path)
    Console.println("         actual : ", actual)
    reportImageDifference(&difference, &expected, image)
    @assert(false)
}

private
{
    struct ImageDifference
    {
        sameSize:        bool
        differentPixels: u64
        maxChannelDelta: u8
        firstX:          s32
        firstY:          s32
        firstExpected:   Color
        firstActual:     Color
    }

    func isWithinTolerance(difference: const *ImageDifference, options: ImageGoldenOptions)->bool
    {
        return difference.sameSize and difference.differentPixels <= options.maxDifferentPixels
    }

    func compareImages(expected, actual: const *Image, options: ImageGoldenOptions)->ImageDifference
    {
        var result: retval
        result.sameSize = expected.width == actual.width and expected.height == actual.height
        if !result.sameSize do
            return result

        for [y] in actual.height
        {
            for [x] in actual.width
            {
                let expectedColor = expected.pixelColor(x, y)
                let actualColor   = actual.pixelColor(x, y)
                let deltaA        = Math.abs(cast(s32) expectedColor.a - actualColor.a)
                let deltaR        = Math.abs(cast(s32) expectedColor.r - actualColor.r)
                let deltaG        = Math.abs(cast(s32) expectedColor.g - actualColor.g)
                let deltaB        = Math.abs(cast(s32) expectedColor.b - actualColor.b)
                let delta         = Math.max(Math.max(deltaA, deltaR), Math.max(deltaG, deltaB))
                result.maxChannelDelta = Math.max(result.maxChannelDelta, cast(u8) delta)
                if delta <= options.maxChannelDelta do
                    continue

                result.differentPixels += 1
                if result.differentPixels == 1
                {
                    result.firstX        = x
                    result.firstY        = y
                    result.firstExpected = expectedColor
                    result.firstActual   = actualColor
                }
            }
        }

        return result
    }

    func reportImageDifference(difference: const *ImageDifference, expected, actual: const *Image)
    {
        if !difference.sameSize
        {
            Console.println("         size   : ", expected.width, "x", expected.height, " expected, ", actual.width, "x", actual.height, " produced")
            return
        }

        Console.println("         pixels : ", difference.differentPixels, " outside tolerance")
        Console.println("         delta  : ", difference.maxChannelDelta, " maximum channel difference")
        if difference.differentPixels
        {
            Console.println("         first  : (", difference.firstX, ", ", difference.firstY, ") expected ", difference.firstExpected.argb, ", produced ", difference.firstActual.argb)
        }
    }

    func writeImage(image: const *Image, path: string)->bool
    {
        let dir = Path.directoryName(path)
        if dir != null and !Directory.exists(dir)
        {
            catch Directory.create(dir) as errDir
            if errDir != null
            {
                Console.println("[image] cannot create ", dir)
                reportSandboxRefusal(dir)
                return false
            }
        }

        discard catch image.save(path) as errWrite
        if errWrite != null
        {
            Console.println("[image] cannot write ", path)
            reportSandboxRefusal(path)
            return false
        }

        return true
    }

    // Names the isolation when it is what refused the write. A golden lives in the module source
    // tree, outside the sandbox a test runs in, so recording one depends on the launcher having
    // granted that tree as the corpus. Without the explanation the failure reads as a permission
    // problem on a file the reader can see is perfectly writable.
    func reportSandboxRefusal(path: string)
    {
        if !Env.isSandboxed() or Env.isInsideCorpus(path) do
            return

        Console.println("         it is outside the sandbox at ", Env.sandboxRoot())
        Console.println("         run the test with 'swag.sandbox.corpus=<directory>' to record there")
    }

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
                reportSandboxRefusal(dir)
                return
            }
        }

        discard catch File.writeAllBytes(path, @mkslice(@dataof(text), @countof(text))) as errWrite
        if errWrite != null
        {
            Console.println("[golden] cannot write ", path)
            reportSandboxRefusal(path)
        }
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
