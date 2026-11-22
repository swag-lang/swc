#global public
#global namespace Testing

using Swag, Core

// Configures tolerated differences for image-to-image and PNG-golden comparisons.
struct ImageGoldenOptions
{
    public
    {
        maxChannelDelta:    u8       // Maximum absolute difference accepted for each ARGB channel.
        maxDifferentPixels: u64      // Maximum number of pixels allowed outside the channel tolerance.
        acceptEdgeChoice:   bool     // Whether a renderer comparison accepts a boundary between two areas sitting one pixel off.
    }
}

// Compares the display list recorded by 'painter' against the golden named 'name'.
//
// The painter is serialized with [[Pixel.Testing.dumpPainter]], so this asserts on the *commands* a
// drawing emits, not on the pixels it would produce: it needs no GPU and no window, and its
// result is identical on every machine.
//
// Goldens live in 'src/tests/goldens', beside the categorized cases folder, one '.txt' file per name.
// 'name' may contain '/' to group goldens in sub-folders.
//
// Golden operations are supported only in Release, where their reference output is produced.
// DevMode tests the behavior and safety paths without comparing or generating snapshots.
//
// There is no recording mode and no flag to pass. A name with no golden yet writes one and passes,
// so a new test starts by producing its reference; the file then shows up as untracked, which is
// where it gets reviewed and committed. A name whose golden no longer matches writes the produced
// text next to it as '<name>.actual.txt', prints the first differing line, and fails the test
// through [[Swag.check]]: the test goes on, so one run reports every golden it moved. Accepting
// the new output is therefore a copy, which `tools/goldens.bat accept` does in bulk.
//
// These checks are supported only when the program is built as Release.
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
// Behaves exactly like [[Pixel.Testing.assertGolden]] but takes the snapshot text directly, for callers
// that build their own normalized representation. Both sides are compared with end of lines
// normalized to '\n', so a CRLF checkout never changes the outcome.
// Snapshot checks require the Release program configuration.
func assertGoldenText(text: string, name: string, loc = #callerlocation)
{
    #static if #cfg != "release"
    {
        Swag.check(false, "golden checks require the Release configuration", loc)
        return
    }

    let path = goldenPath(name, ".txt", loc)

    // No golden yet: write one and let the test pass. It is loud on purpose -- an untracked file
    // appearing in the working tree is what turns a mistyped name into something visible rather
    // than a test that silently asserts nothing forever.
    if not File.exists(path)
    {
        writeText(path.toString(), text)
        Console.println("[golden] created ", name, " -- review it before committing")
        Console.println("         ", path)
        return
    }

    let expected = catch File.readAllText(path, normalizeEol: true)
    {
        Console.println("[golden] cannot read ", path)
        Swag.check(false, "the golden cannot be read", loc)
        return
    }

    if expected.toString() == text do
        return

    let actual = actualPath(path.toString(), ".txt", ".actual.txt")
    writeText(actual.toString(), text)
    reportDiff(name, path.toString(), actual.toString(), expected.toString(), text)
    Swag.check(false, "the text differs from its golden", loc)
}

// Compares two owned pixel buffers with the same bounded tolerance as image goldens.
//
// `expected` and `actual` must be valid images. Dimensions must match exactly. A channel delta
// at or below [[Pixel.Testing.ImageGoldenOptions.maxChannelDelta]] is accepted; at most
// [[Pixel.Testing.ImageGoldenOptions.maxDifferentPixels]] pixels may exceed it. A failed comparison
// writes `<name>.expected.png` and `<name>.actual.png` beside the calling test, and fails it
// through [[Swag.check]] without stopping it.
// The check remains active when Pixel is built as a release dependency.
func assertImagesNear(expected, actual: const *Image, name: string, options: ImageGoldenOptions = {}, loc = #callerlocation)
{
    Swag.require(expected != null and expected.isValid(), "expected image needs allocated pixels")
    Swag.require(actual != null and actual.isValid(), "actual image needs allocated pixels")

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
    Swag.check(false, "the pixels differ from the expected image", loc)
}

// Compares what the CPU and a GPU renderer drew from the same scene.
//
// `cpu` and `gpu` must be valid images of the same size. This is the comparison of the renderer
// parity campaign, and it accepts what separates one graphics device from another: each channel
// may be off by three levels anywhere, for rounding in blending, and by a share of the contrast
// around the pixel, for antialiasing and filtering. A flat area therefore only gets the rounding
// slack, while a shape that moved by a pixel, lost a stroke or changed color costs the whole
// contrast and is a difference. Rejected pixels count only when they form a shape.
// [[Pixel.Testing.ImageGoldenOptions.maxChannelDelta]] raises the rounding slack and
// [[Pixel.Testing.ImageGoldenOptions.maxDifferentPixels]] accepts that many pixels of difference.
//
// [[Pixel.Testing.ImageGoldenOptions.acceptEdgeChoice]] also accepts a boundary between two
// areas that sits exactly one pixel off. That is what a picture drawn in pixel mode shows where
// a pixel centre maps onto a texel boundary: OpenGL leaves the side to the implementation, so
// one row or column of the picture reads the neighbouring texel. A boundary two pixels off, and
// a rule or stem that is missing rather than moved, stay differences. The option cannot tell
// such a tie from a filled shape whose edge really moved by one pixel, so a dedicated parity
// scene leaves it off and avoids the tie instead; the parity sweep, which draws real
// application scenes, turns it on.
//
// A difference writes `<name>.parity.cpu.png` and `<name>.parity.gpu.png` in the goldens folder
// of the calling test, reports its first pixel, and fails the test through [[Swag.check]]
// without stopping it. Neither file is a golden: a real divergence is fixed in the renderer.
// The check remains active when Pixel is built as a release dependency.
func assertRenderersAgree(cpu, gpu: const *Image, name: string, options: ImageGoldenOptions = {}, loc = #callerlocation)
{
    Swag.require(cpu != null and cpu.isValid(), "CPU image needs allocated pixels")
    Swag.require(gpu != null and gpu.isValid(), "GPU image needs allocated pixels")

    var tolerance = options
    tolerance.maxChannelDelta = Math.max(tolerance.maxChannelDelta, GpuChannelSlack)
    let difference = compareGpuImage(cpu, gpu, tolerance)
    if isWithinTolerance(&difference, tolerance) do
        return

    let cpuPath = goldenPath(name, ".parity.cpu.png", loc)
    let gpuPath = goldenPath(name, ".parity.gpu.png", loc)
    discard writeImage(cpu, cpuPath.toString())
    discard writeImage(gpu, gpuPath.toString())

    Console.println("[parity] renderers diverge for ", name)
    Console.println("         cpu    : ", cpuPath)
    Console.println("         gpu    : ", gpuPath)
    reportImageDifference(&difference, cpu, gpu)
    Swag.check(false, "the CPU and GPU renderers diverge", loc)
}

// Compares owned pixels against the PNG golden named `name`.
//
// Goldens live under `src/tests/goldens/<name>.png`. A PNG golden is a CPU reference: only
// [[Pixel.RenderCpu]] produces the same pixels on every machine, so a golden is recorded,
// compared and replaced from a CPU render and from nothing else. The comparison is exact.
// A missing golden is created and passes, like [[Pixel.Testing.assertGolden]]. A mismatch writes
// `<name>.actual.png`, reports its first differing pixel, and fails the test through
// [[Swag.check]], which lets it compare its other goldens.
//
// GUI headless hosts produce CPU pixels. Tests that compare renderers explicitly use
// [[Pixel.Testing.assertRenderersAgree]].
//
// [[Pixel.Testing.ImageGoldenOptions]] can tolerate bounded codec or raster differences; both
// limits default to exact comparison. Golden recording and comparison are supported only in
// Release, so the reference and candidate always use the same program configuration.
func assertImageGolden(image: const *Image, name: string, options: ImageGoldenOptions = {}, loc = #callerlocation)
{
    #static if #cfg != "release"
    {
        Swag.check(false, "golden checks require the Release configuration", loc)
        return
    }

    Swag.require(image != null and image.isValid(), "image golden needs allocated pixels")
    let path = goldenPath(name, ".png", loc)

    if not File.exists(path)
    {
        if not writeImage(image, path.toString())
        {
            Swag.check(false, "the golden cannot be recorded", loc)
            return
        }

        Console.println("[golden] created ", name, " -- review it before committing")
        Console.println("         ", path)
        return
    }

    let expected = catch Image.load(path.toString())
    {
        Console.println("[golden] cannot read ", path)
        Swag.check(false, "the golden cannot be read", loc)
        return
    }

    let difference = compareImages(&expected, image, options)
    let actual     = actualPath(path.toString(), ".png", ".actual.png")
    if isWithinTolerance(&difference, options)
    {
        // A candidate an earlier run left is stale once the golden matches again.
        discard catch File.delete(actual)
        return
    }

    discard writeImage(image, actual.toString())

    Console.println("[golden] pixels differ for ", name)
    Console.println("         golden : ", path)
    Console.println("         actual : ", actual)
    reportImageDifference(&difference, &expected, image)
    Swag.check(false, "the pixels differ from the golden", loc)
}

// Levels each channel of a GPU image may be off by anywhere, for rounding in blending.
private const GpuChannelSlack = 3'u8

// Share of the contrast around a pixel a GPU image may also be off by, for antialiasing and
// filtering. A shape moved by one pixel costs the whole contrast, so it stays a difference.
private const GpuContrastShare = 0.35'f32

private
{
    internal struct ImageDifference
    {
        sameSize:        bool
        differentPixels: u64
        maxChannelDelta: u8
        firstX:          s32
        firstY:          s32
        firstExpected:   Color
        firstActual:     Color
    }

    func isWithinTolerance(difference: const *ImageDifference, options: ImageGoldenOptions)->bool => difference.sameSize and difference.differentPixels <= options.maxDifferentPixels

    // Golden PNGs and rendered surfaces usually use different channel orders. Read their
    // packed bytes directly; only associated translucent pixels need logical conversion.
    struct ComparisonPixels
    {
        image:  const *Image
        packed: bool
        red:    u32
        blue:   u32
    }

    impl ComparisonPixels
    {
        func create(image: const *Image)->ComparisonPixels
        {
            var result: #returntype
            result.image  = image
            result.packed = image.pixelFormat == .RGB8 or
                            image.pixelFormat == .RGBA8 or
                            image.pixelFormat == .BGR8 or
                            image.pixelFormat == .BGRA8
            let blueFirst = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
            result.red  = blueFirst ? 2 : 0
            result.blue = blueFirst ? 0 : 2
            return result
        }

        #[Swag.Inline]
        mtd const color(row: const [*] u8, x, y: s32)->Color
        {
            if not .packed do
                return .image.pixelColor(x, y)
            let pixel = row + cast(u64, x) * .image.bytesPerPixel
            let alpha = .image.bytesPerPixel == 4 ? pixel[3] : 255'u8
            if .image.alphaMode == .Premultiplied and alpha != 255 do
                return .image.pixelColor(x, y)
            var result: #returntype
            result.r = pixel[.red]
            result.g = pixel[1]
            result.b = pixel[.blue]
            result.a = alpha
            return result
        }

        // Reads the pixel at `(x, y)`, clamped to the image the way a border is extended.
        mtd const at(x, y: s32)->Color
        {
            let px  = Math.clamp(x, 0, .image.width - 1)
            let py  = Math.clamp(y, 0, .image.height - 1)
            let row = .image.pixels.storage() + cast(u64, .image.height - py - 1) * .image.rowStride
            return .color(row, px, py)
        }
    }

    func channelDelta(expected, actual: Color)->s32
    {
        let deltaA = Math.abs(cast(s32, expected.a) - actual.a)
        let deltaR = Math.abs(cast(s32, expected.r) - actual.r)
        let deltaG = Math.abs(cast(s32, expected.g) - actual.g)
        let deltaB = Math.abs(cast(s32, expected.b) - actual.b)
        return Math.max(deltaA, deltaR, deltaG, deltaB)
    }

    // Returns the widest channel range of the 3x3 neighbourhood of `(x, y)` across both images.
    func localContrast(expected, actual: ComparisonPixels, x, y: s32)->s32
    {
        var low:  [4] s32 = [255, 255, 255, 255]
        var high: [4] s32 = [0, 0, 0, 0]
        for dy in -1 to 1
        {
            for dx in -1 to 1
            {
                for side in 2
                {
                    let color = side == 0 ? expected.at(x + dx, y + dy) : actual.at(x + dx, y + dy)
                    let channels: [4] s32 = [color.a, color.r, color.g, color.b]
                    for i in 4
                    {
                        low[i]  = Math.min(low[i], channels[i])
                        high[i] = Math.max(high[i], channels[i])
                    }
                }
            }
        }

        return Math.max(high[0] - low[0], high[1] - low[1], high[2] - low[2], high[3] - low[3])
    }

    // Says whether `(x, y)` only shows a boundary between two areas sitting one pixel off.
    //
    // The reference pixel then continues the area on one side, and the drawn pixel already shows
    // the area on the other side: the boundary between them moved across this pixel and no
    // further. A rule or a stem one pixel thick matches neither of its neighbours in the
    // reference, so losing it is never such a choice.
    func isEdgeChoice(expected, actual: ComparisonPixels, x, y: s32, slack: u8)->bool
    {
        let reference      = expected.at(x, y)
        let drawn          = actual.at(x, y)
        let stepX: [4] s32 = [0, 0, 1, -1]
        let stepY: [4] s32 = [1, -1, 0, 0]
        for side in 4
        {
            let dx = stepX[side]
            let dy = stepY[side]
            if channelDelta(reference, expected.at(x - dx, y - dy)) <= slack and
               channelDelta(drawn, expected.at(x + dx, y + dy)) <= slack do
                return true
        }

        return false
    }

    // Compares what a GPU drew against a CPU reference, the way two graphics devices differ.
    //
    // A pixel is accepted while its largest channel difference stays within
    // `options.maxChannelDelta` plus [[GpuContrastShare]] of the contrast around it. A flat area
    // therefore only gets the rounding slack, and an edge gets a share of its own contrast. A
    // rejected pixel counts as a difference when two of its neighbours are rejected too: a real
    // defect is a shape, while a lone pixel is a corner the two rasterizers closed differently.
    internal func compareGpuImage(expected, actual: const *Image, options: ImageGoldenOptions)->ImageDifference
    {
        var result: #returntype
        result.sameSize = expected.width == actual.width and expected.height == actual.height
        if not result.sameSize do
            return result

        let expectedPixels = ComparisonPixels.create(expected)
        let actualPixels   = ComparisonPixels.create(actual)
        let width          = actual.width
        let height         = actual.height

        // Mark the pixels neither tolerance explains.
        var rejected: Array'bool
        rejected.resize(cast(u64, width) * cast(u64, height))
        var anyRejected = false
        for y in height
        {
            for x in width
            {
                let delta = channelDelta(expectedPixels.at(x, y), actualPixels.at(x, y))
                result.maxChannelDelta = Math.max(result.maxChannelDelta, cast(u8, delta))
                if delta <= options.maxChannelDelta do
                    continue

                let contrast = localContrast(expectedPixels, actualPixels, x, y)
                if cast(f32, delta) <= options.maxChannelDelta + GpuContrastShare * contrast do
                    continue
                if options.acceptEdgeChoice and isEdgeChoice(expectedPixels, actualPixels, x, y, options.maxChannelDelta) do
                    continue

                rejected[cast(u64, y) * cast(u64, width) + cast(u64, x)] = true
                anyRejected = true
            }
        }

        if not anyRejected do
            return result

        // Keep the rejected pixels that form a shape.
        for y in height
        {
            for x in width
            {
                if not rejected[cast(u64, y) * cast(u64, width) + cast(u64, x)] do
                    continue

                var cluster = 0
                for ny in Math.max(y - 1, 0) to Math.min(y + 1, height - 1)
                {
                    for nx in Math.max(x - 1, 0) to Math.min(x + 1, width - 1)
                    {
                        if rejected[cast(u64, ny) * cast(u64, width) + cast(u64, nx)] do
                            cluster += 1
                    }
                }

                if cluster < 3 do
                    continue

                result.differentPixels += 1
                if result.differentPixels == 1
                {
                    result.firstX        = x
                    result.firstY        = y
                    result.firstExpected = expectedPixels.at(x, y)
                    result.firstActual   = actualPixels.at(x, y)
                }
            }
        }

        return result
    }

    internal func compareImages(expected, actual: const *Image, options: ImageGoldenOptions)->ImageDifference
    {
        var result: #returntype
        result.sameSize = expected.width == actual.width and expected.height == actual.height
        if not result.sameSize do
            return result

        let expectedPixels = ComparisonPixels.create(expected)
        let actualPixels   = ComparisonPixels.create(actual)
        let sameStorage    = expectedPixels.packed and
                             actualPixels.packed and
                             expected.pixelFormat == actual.pixelFormat and
                             expected.alphaMode == actual.alphaMode
        if options.maxChannelDelta == 0 and
           expectedPixels.packed and
           actualPixels.packed and
           expected.bytesPerPixel == actual.bytesPerPixel and
           expected.alphaMode == .Straight and
           actual.alphaMode == .Straight and
           not sameStorage
        {
            // PNG stores red before blue, while headless surfaces return BGRA. Convert once with
            // the packed SIMD path, then compare whole rows instead of computing four deltas per pixel.
            let normalizedExpected = expected.convertedTo(actual.pixelFormat)
            let rowBytes  = cast(u64, actual.width) * actual.bytesPerPixel
            var rowsMatch = true
            for y in actual.height
            {
                let expectedRow = normalizedExpected.pixels.storage() + cast(u64, normalizedExpected.height - y - 1) * normalizedExpected.rowStride
                let actualRow   = actual.pixels.storage() + cast(u64, actual.height - y - 1) * actual.rowStride
                if Memory.compare(expectedRow, actualRow, rowBytes) != 0
                {
                    rowsMatch = false
                    break
                }
            }

            if rowsMatch do
                return result
        }

        for y in actual.height
        {
            let expectedRow = expected.pixels.storage() + cast(u64, expected.height - y - 1) * expected.rowStride
            let actualRow   = actual.pixels.storage() + cast(u64, actual.height - y - 1) * actual.rowStride
            if sameStorage and Memory.compare(expectedRow, actualRow, actual.rowStride) == 0 do
                continue
            for x in actual.width
            {
                let expectedColor = expectedPixels.color(expectedRow, x, y)
                let actualColor   = actualPixels.color(actualRow, x, y)
                let deltaA        = Math.abs(cast(s32, expectedColor.a) - actualColor.a)
                let deltaR        = Math.abs(cast(s32, expectedColor.r) - actualColor.r)
                let deltaG        = Math.abs(cast(s32, expectedColor.g) - actualColor.g)
                let deltaB        = Math.abs(cast(s32, expectedColor.b) - actualColor.b)
                let delta         = Math.max(deltaA, deltaR, deltaG, deltaB)
                result.maxChannelDelta = Math.max(result.maxChannelDelta, cast(u8, delta))
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
        if not difference.sameSize
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
        if dir != null and not Directory.exists(dir)
        {
            catch Directory.create(dir)
            {
                Console.println("[image] cannot create ", dir)
                reportSandboxRefusal(dir)
                return false
            }
        }

        discard catch image.save(path)
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
        if not Env.isSandboxed() or Env.isInsideCorpus(path) do
            return

        Console.println("         it is outside the sandbox at ", Env.sandboxRoot())
        Console.println("         run the test with 'swag.sandbox.corpus=<directory>' to record there")
    }

    // Categorized test sources share the module's src/tests/goldens corpus.
    func goldenPath(name, extension: string, loc: Swag.SourceCodeLocation)->String
    {
        var testRoot = Path.directoryName(loc.fileName)
        var dir      = testRoot
        while dir != null
        {
            if Path.fileName(dir) == "cases" or Path.fileName(dir) == "helpers"
            {
                testRoot = Path.directoryName(dir)
                break
            }

            dir = Path.directoryName(dir)
        }

        let folder = Path.combine(testRoot, "goldens")

        var file = String.from(name)
        file += extension
        return Path.combine(folder.toString(), file.toString())
    }

    // Replaces the `extension` of a golden path with the `suffix` of what a run produced instead.
    func actualPath(path, extension, suffix: string)->String
    {
        var result = String.from(path)
        result.removeBack(extension.count)
        result += suffix
        return result
    }

    // Writes UTF-8 bytes with the '\n' separators the text already carries. Going through
    // 'writeAllBytes' rather than a text writer guarantees the stored file keeps single '\n',
    // whatever the platform default is.
    func writeText(path: string, text: string)
    {
        let dir = Path.directoryName(path)
        if dir != null and not Directory.exists(dir)
        {
            catch Directory.create(dir)
            {
                Console.println("[golden] cannot create ", dir)
                reportSandboxRefusal(dir)
                return
            }
        }

        discard catch File.writeAllBytes(path, Swag.makeSlice(text.buffer, text.count))
        {
            Console.println("[golden] cannot write ", path)
            reportSandboxRefusal(path)
        }
    }

    func splitLines(text: string)->Array'String
    {
        var result: #returntype
        var cur:    String

        for i in text.count
        {
            if text[i] == '\n'u8
            {
                result.add(cur)
                cur.clear()
            }
            else
            {
                cur.append(text[i])
            }
        }

        if not cur.isEmpty() do
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
        for i in common
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
