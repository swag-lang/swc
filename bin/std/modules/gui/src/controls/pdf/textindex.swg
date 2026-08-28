#global internal
#global namespace Pdf

using Core, Core.Math, Pixel

// How far two runs may sit apart vertically, as a share of the taller one, and still be read as
// one line; and the horizontal gap, as a share of the run height, past which two runs on one
// line are two words rather than one split by kerning.
private const TextLineOverlap = 0.5'f32
private const TextWordGap     = 0.18'f32

// One code of a run: the byte range it decoded to inside the run's text, and the horizontal
// span it covers in the item's local units.
#[Swag.NoDoc]
public struct TextCode
{
    byteStart: u32
    byteEnd:   u32
    x0, x1:    f32
}

// The part of [[Pdf.TextIndex.text]] one page item contributed, with the geometry to put any
// slice of it back on the page.
#[Swag.NoDoc]
public struct TextRun
{
    item:      u32     // Index of the page item.
    textStart: u64     // Byte range this run holds inside the page text.
    textEnd:   u64
    rect:      Rectangle     // Page-space bounding rectangle.

    // Per-code geometry only exists for an upright run: a rotated or sheared one keeps its
    // bounding rectangle and answers at run granularity.
    axisAligned: bool
    originX:     f32                // Page-space x of the run's local origin.
    scaleX:      f32                // Local-to-page horizontal scale.
    codes:       Array'TextCode     // Per-code spans, in text order.
}

// The text of one page in reading order, with the geometry to hit-test, select, and highlight
// it. Runs are ordered as they read — lines from top to bottom, each line from left to right —
// and the page text inserts one space per word gap and one line feed per line break, which is
// the plain-text shape a search or a copy expects.
#[Swag.NoDoc]
public struct TextIndex
{
    text: String
    runs: Array'TextRun
}

// Reading-order construction state for one run.
private struct TextRunSeed
{
    run:     TextRun
    text:    String
    yCenter: f32
    height:  f32
    x:       f32
}

impl TextIndex
{
    // Indexes every upright and rotated text item of a page.
    func build(page: const *Page)->TextIndex
    {
        var result: retval

        var seeds: Array'TextRunSeed
        for item, itemIndex in page.items
        {
            if item.kind != .Text or item.text.isEmpty() do
                continue
            var seed = seedRun(page, item, cast(u32) itemIndex)
            if seed.run.rect.width <= 0 or seed.run.rect.height <= 0 do
                continue
            seeds.add(#move seed)
        }

        // Lines from top to bottom, then left to right inside a line: content-stream order is
        // paint order, which places a page's header after its watermark and its columns in
        // whatever order the writer emitted them.
        seeds.sort(func(a, b)
        {
            if a.yCenter < b.yCenter do
                return -1
            if a.yCenter > b.yCenter do
                return 1
            if a.x < b.x do
                return -1
            if a.x > b.x do
                return 1
            return 0
        })

        var lineStart = 0'u64
        var scan      = 0'u64
        while scan < seeds.count
        {
            // A line ends where the next run no longer overlaps it vertically.
            var lineEnd    = scan + 1
            var lineBottom = seeds[scan].yCenter + seeds[scan].height * TextLineOverlap
            while lineEnd < seeds.count and seeds[lineEnd].yCenter < lineBottom
            {
                lineBottom = Math.max(lineBottom, seeds[lineEnd].yCenter + seeds[lineEnd].height * TextLineOverlap)
                lineEnd    += 1
            }

            sortLineByX(&seeds, scan, lineEnd)
            result.emitLine(&seeds, scan, lineEnd, lineStart != 0)
            lineStart = 1
            scan      = lineEnd
        }

        return result
    }

    // Appends one line's runs to the page text, separating words by the gaps between them.
    private mtd emitLine(seeds: *Array'TextRunSeed, first, last: u64, breakBefore: bool)
    {
        if breakBefore do
            .text += "\n"

        var previousRight = 0.0'f32
        for index in first until last
        {
            let seed = &seeds[index]
            if index != first
            {
                let gap = seed.run.rect.x - previousRight
                if gap > seed.run.rect.height * TextWordGap and !.text.isEmpty() and .text.back() != ' 'u8 and seed.text.toString()[0] != ' 'u8 do
                    .text += " "
            }

            var run = seed.run
            run.textStart = .text.length
            .text         += seed.text
            run.textEnd   = .text.length
            .runs.add(#move run)
            previousRight = Math.max(previousRight, seed.run.rect.right())
        }
    }

    private func sortLineByX(seeds: *Array'TextRunSeed, first, last: u64)
    {
        // Lines are short; a stable insertion keeps equal columns in paint order.
        var i = first + 1
        while i < last
        {
            var j = i
            while j > first and seeds[j].x < seeds[j - 1].x
            {
                swap(&seeds[j], &seeds[j - 1])
                j -= 1
            }

            i += 1
        }
    }

    // Builds the geometry of one text item.
    private func seedRun(page: const *Page, item: const *Item, itemIndex: u32)->TextRunSeed
    {
        var result: retval
        result.run.item = itemIndex
        result.text     = item.text

        let m           = item.transform
        let axisAligned = Math.abs(m.m12) < 0.001 and Math.abs(m.m21) < 0.001 and m.m11 > 0 and m.m22 > 0

        // The local box of the run: the origin sits one em above the baseline, so the run
        // occupies local y in [0, fontSize].
        var codes: Array'TextCode
        let width = itemLocalWidth(page, item, &codes)

        if axisAligned
        {
            result.run.axisAligned = true
            result.run.originX     = m.tx
            result.run.scaleX      = m.m11
            result.run.rect        = {m.tx, m.ty, width * m.m11, item.fontSize * m.m22}
            result.run.codes       = #move codes
        }
        else
        {
            // A rotated run keeps the bounding box of its transformed corners.
            var minX              = Swag.F32.Max
            var minY              = Swag.F32.Max
            var maxX              = -Swag.F32.Max
            var maxY              = -Swag.F32.Max
            let cornersX: [4] f32 = [0, width, 0, width]
            let cornersY: [4] f32 = [0, 0, item.fontSize, item.fontSize]
            for corner in 4
            {
                let px = m.m11 * cornersX[corner] + m.m21 * cornersY[corner] + m.tx
                let py = m.m12 * cornersX[corner] + m.m22 * cornersY[corner] + m.ty
                minX = Math.min(minX, px)
                minY = Math.min(minY, py)
                maxX = Math.max(maxX, px)
                maxY = Math.max(maxY, py)
            }

            result.run.rect = {minX, minY, maxX - minX, maxY - minY}
        }

        result.yCenter = result.run.rect.vertCenter()
        result.height  = result.run.rect.height
        result.x       = result.run.rect.x
        return result
    }

    // Returns the local width of a run and fills its per-code spans.
    //
    // A run whose font resource is missing has no decoded codes; its geometry is estimated from
    // the standard face the decoder matched, one rune per code.
    private func itemLocalWidth(page: const *Page, item: const *Item, codes: *Array'TextCode)->f32
    {
        var x = 0.0'f32
        if item.textCodes.count and item.textCodes.count == item.textAdvances.count and item.fontIndex < page.fonts.count
        {
            let font      = &page.fonts[item.fontIndex]
            var byteStart = 0'u64
            for code, index in item.textCodes
            {
                let codeString = font.codeText(code)
                let byteEnd    = Math.min(byteStart + codeString.length, item.text.length)
                codes.add({cast(u32) byteStart, cast(u32) byteEnd, x, x + item.textAdvances[index]})
                x         += item.textAdvances[index]
                byteStart = byteEnd
            }

            // The decoded text and the codes can disagree on a malformed file; keep the byte
            // ranges inside the text whatever happened.
            if byteStart < item.text.length and codes.count do
                codes.backPtr().byteEnd = cast(u32) item.text.length
            return x
        }

        let source = item.text.toString()
        var scan   = 0'u64
        while scan < @countof(source)
        {
            let {value, eat} = Utf8.decodeRune(source[scan to])
            let advance      = item.standardFont.glyphWidth(value) * item.fontSize
            codes.add({cast(u32) scan, cast(u32) (scan + eat), x, x + advance})
            x    += advance
            scan += eat
        }

        return x
    }

    // Returns the byte offset in the page text nearest a page-space point, with how far the
    // answering run was. `Swag.U64.Max` when the page holds no text.
    mtd const positionAt(point: Point)->{ offset: u64, distance: f32 }
    {
        var result: retval
        result.offset   = Swag.U64.Max
        result.distance = Swag.F32.Max

        for run in .runs
        {
            var dx = 0.0'f32
            if point.x < run.rect.x do
                dx = run.rect.x - point.x
            elif point.x > run.rect.right() do
                dx = point.x - run.rect.right()
            var dy = 0.0'f32
            if point.y < run.rect.y do
                dy = run.rect.y - point.y
            elif point.y > run.rect.bottom() do
                dy = point.y - run.rect.bottom()

            // A run on the pointed line beats every run of another line, however close.
            let distance = dy * 4096 + dx
            if distance >= result.distance do
                continue

            result.distance = distance
            result.offset   = .offsetInRun(run, point.x)
        }

        return result
    }

    private mtd const offsetInRun(run: const *TextRun, pageX: f32)->u64
    {
        if !run.axisAligned or !run.codes.count or run.scaleX <= 0 do
            return pageX < run.rect.horzCenter() ? run.textStart : run.textEnd

        let localX = (pageX - run.originX) / run.scaleX
        for code in run.codes
        {
            if localX >= code.x1 do
                continue
            let middle = (code.x0 + code.x1) * 0.5
            return run.textStart + (localX < middle ? code.byteStart : code.byteEnd)
        }

        return run.textEnd
    }

    // Appends the page-space rectangles covering a byte range of the page text.
    mtd const rangeRects(start, end: u64, rects: *Array'Rectangle)
    {
        if end <= start do
            return

        for run in .runs
        {
            if end <= run.textStart or start >= run.textEnd do
                continue

            var rect = run.rect
            if run.axisAligned and run.codes.count and (start > run.textStart or end < run.textEnd)
            {
                var x0 = Swag.F32.Max
                var x1 = -Swag.F32.Max
                let lo = start > run.textStart ? start - run.textStart : 0
                let hi = end < run.textEnd ? end - run.textStart : run.textEnd - run.textStart
                for code in run.codes
                {
                    if code.byteEnd <= lo or code.byteStart >= hi do
                        continue
                    x0 = Math.min(x0, code.x0)
                    x1 = Math.max(x1, code.x1)
                }

                if x1 <= x0 do
                    continue
                rect.x     = run.originX + x0 * run.scaleX
                rect.width = (x1 - x0) * run.scaleX
            }

            rects.add(rect)
        }
    }

    // Returns the word around a byte offset of the page text, the double-click gesture.
    mtd const wordRangeAt(offset: u64)->{ start: u64, end: u64 }
    {
        var result: retval
        let source = .text.toString()
        if !@countof(source) do
            return result

        var starts: Array'u64
        var words:  Array'bool
        var scan = 0'u64
        while scan < @countof(source)
        {
            let {value, eat} = Utf8.decodeRune(source[scan to])
            starts.add(scan)
            words.add(Unicode.isLetterOrDigit(value) or value == '_'rune)
            scan += eat
        }

        starts.add(scan)
        let position  = Math.min(offset, @countof(source) - 1)
        var runeIndex = 0'u64
        for i in words.count where starts[i] <= position do
            runeIndex = i

        var lo = runeIndex
        var hi = runeIndex
        if words[runeIndex]
        {
            while lo and words[lo - 1] do
                lo -= 1
            while hi + 1 < words.count and words[hi + 1] do
                hi += 1
        }

        result.start = starts[lo]
        result.end   = starts[hi + 1]
        return result
    }
}
