#global internal

using Core, Gui, Pixel

struct ComparisonOptions
{
    ignoreWhitespace: bool
    ignoreCase:       bool
    ignoreEndings:    bool
    unified:          bool
}

struct ComparisonRow
{
    left:    u32 = Swag.U32.Max
    right:   u32 = Swag.U32.Max
    changed: bool
}

struct ComparisonLine
{
    text: String
    key:  String
}

struct TextComparison
{
    left:    Array'ComparisonLine
    right:   Array'ComparisonLine
    rows:    Array'ComparisonRow
    changes: Array'u64
}

impl TextComparison
{
    const WorkLimit = 4_000_000'u64
    const ByteLimit = 8 * 1024 * 1024'u64
    const LookAhead = 64'u64

    mtd compare(left, right: string, options: ComparisonOptions)
    {
        .left  = .lines(left, options)
        .right = .lines(right, options)
        .align()
    }

    mtd compareBytes(left, right: const [..] u8)
    {
        .left  = .hexLines(left)
        .right = .hexLines(right)
        .align()
    }

    mtd compareReports(left, right: const *Viewers.Binary.Report)
    {
        .left  = reportLines(left)
        .right = reportLines(right)
        .align()
        .changes.clear()
        var previousChanged = false
        for &row, index in .rows
        {
            if row.left != Swag.U32.Max and row.right != Swag.U32.Max do
                row.changed = row.changed or .left[row.left].text != .right[row.right].text
            if row.changed and not previousChanged do
                .changes.add(index)
            previousChanged = row.changed
        }
    }

    private mtd lines(source: string, options: ComparisonOptions)->Array'ComparisonLine
    {
        var result: #returntype
        var start:  u64
        while start < source.count
        {
            var end = start
            while end < source.count and source[end] != '\r' and source[end] != '\n' do
                end += 1
            var next = end
            if next < source.count
            {
                next += 1
                if source[end] == '\r' and next < source.count and source[next] == '\n' do
                    next += 1
            }

            let text = source[start until end]
            var key: String
            if options.ignoreWhitespace
            {
                var offset: u64
                while offset < text.count
                {
                    let decoded = Utf8.decodeRune(text[offset to])
                    if not Unicode.isSpace(decoded.c) do
                        key += text[offset until offset + decoded.eat]
                    offset += decoded.eat
                }
            }
            else
            {
                key = text
            }

            if options.ignoreCase do
                key = String.toLower(key.toString(), .Unicode)
            if not options.ignoreEndings do
                key += source[end until next]
            result.add({text: String.from(text), key: #move key})
            start = next
        }

        return result
    }

    private mtd hexLines(bytes: const [..] u8)->Array'ComparisonLine
    {
        const Digits = "0123456789ABCDEF"
        var result: #returntype
        for offset in (bytes.count + 15) / 16
        {
            let at = offset * 16
            var text: String
            for byte in bytes[at until Math.min(at + 16, bytes.count)]
            {
                if not text.isEmpty() do
                    text += ' '
                text += cast(rune, Digits[byte >> 4])
                text += cast(rune, Digits[byte & 15])
            }

            result.add({text: text, key: #move text})
        }

        return result
    }

    private mtd align()
    {
        .rows.clear()
        .changes.clear()

        let a = .left.count
        let b = .right.count
        var first: u64
        while first < a and first < b and .left[first].key == .right[first].key
        {
            .same(first, first)
            first += 1
        }

        var endA = a
        var endB = b
        while endA > first and endB > first and .left[endA - 1].key == .right[endB - 1].key
        {
            endA -= 1
            endB -= 1
        }

        let width  = endB - first + 1
        let height = endA - first + 1
        if height * width <= WorkLimit do
            .alignExact(first, endA, endB)
        else do
            .alignWindow(first, endA, endB)
        for offset in a - endA do
            .same(endA + offset, endB + offset)
    }

    private mtd same(a, b: u64)
    {
        .rows.add({left: cast(u32, a), right: cast(u32, b)})
    }

    private mtd difference(a, endA, b, endB: u64)
    {
        let left  = endA - a
        let right = endB - b
        let count = Math.max(left, right)
        if not count do
            return
        .changes.add(.rows.count)
        for offset in count
        {
            .rows.add({left: offset < left ? cast(u32, a + offset) : Swag.U32.Max,
                       right: offset < right ? cast(u32, b + offset) : Swag.U32.Max, changed: true})
        }
    }

    // A bounded longest-common-subsequence matrix is used for exact alignment of ordinary edits.
    private mtd alignExact(start, endA, endB: u64)
    {
        let width  = endB - start + 1
        let height = endA - start + 1
        var length: Array'u32
        length.resize(width * height)
        for y in reversed(height - 1)
        {
            for x in reversed(width - 1)
            {
                let index = y * width + x
                length[index] = .left[start + y].key == .right[start + x].key ?
                                1 + length[index + width + 1] :
                                Math.max(length[index + width], length[index + 1])
            }
        }

        var y, x: u64
        var previousY, previousX: u64
        while y < height - 1 and x < width - 1
        {
            if .left[start + y].key == .right[start + x].key
            {
                .difference(start + previousY, start + y, start + previousX, start + x)
                .same(start + y, start + x)
                y         += 1
                x         += 1
                previousY = y
                previousX = x
            }
            elif length[(y + 1) * width + x] >= length[y * width + x + 1]
            {
                y += 1
            }
            else
            {
                x += 1
            }
        }

        .difference(start + previousY, endA, start + previousX, endB)
    }

    // Bounds both memory and work for large replacements. Look for the nearest following anchor
    // in either column and accumulate consecutive unmatched lines into one difference.
    private mtd alignWindow(start, endA, endB: u64)
    {
        var a       = start
        var b       = start
        var anchorA = start
        var anchorB = start
        while a < endA and b < endB
        {
            if .left[a].key == .right[b].key
            {
                .difference(anchorA, a, anchorB, b)
                .same(a, b)
                a       += 1
                b       += 1
                anchorA = a
                anchorB = b
                continue
            }

            var found = false
            for i in 1 until Math.min(LookAhead, Math.max(endA - a, endB - b))
            {
                if a + i < endA and .left[a + i].key == .right[b].key
                {
                    a     += i
                    found = true
                    break
                }

                if b + i < endB and .right[b + i].key == .left[a].key
                {
                    b     += i
                    found = true
                    break
                }
            }

            if not found
            {
                a += 1
                b += 1
            }
        }

        .difference(anchorA, endA, anchorB, endB)
    }
}

private func reportLines(report: const *Viewers.Binary.Report)->Array'ComparisonLine
{
    var result: #returntype
    var groups: Array'String
    for &row in report.rows
    {
        groups.resize(row.level)
        var key: String
        if not groups.isEmpty() do
            key = groups.back()
        key += '\n'
        key += row.label
        if row.kind == .Group do
            groups.add(key)
        var text: String
        for row.level do
            text += "  "
        text += row.label
        if not row.value.isEmpty()
        {
            text += "  "
            text += row.value
        }

        result.add({text: #move text, key: #move key})
    }

    return result
}

struct ComparisonLoad
{
    using work: Viewer.BackgroundOperation
    paths:      [2] String
    options:    ComparisonOptions
    kind:       ComparisonKind
    reports:    [2] Viewers.Binary.Report
    text:       TextComparison
    error:      String
}

impl ComparisonLoad
{
    mtd start(parent: *Wnd, paths: [2] String, options: ComparisonOptions, kind: ComparisonKind, reports: [2] (*Viewers.Binary.Report?) = [null, null])
    {
        .paths   = paths
        .options = options
        .kind    = kind
        for report, side in reports do
            .reports[side] = report ? report[] : Viewers.Binary.Report{}
        .error.clear()
        let request = me
        .submit(func|request|()
        {
            if request.kind == .Structured
            {
                request.text.compareReports(&request.reports[0], &request.reports[1])
                for &report in request.reports do
                    report[] = {}
                return
            }

            catch request.read()
            {
                request.error = Viewer.failureText(Swag.err)
                if request.error.isEmpty() do
                    request.error = appStrings().ui_OpenStopped
            }
        },
                parent)
    }

    private mtd read() fail
    {
        var bytes: [2] Array'u8
        for index in 2
        {
            var stream = try File.openRead(.paths[index])
            let size   = try stream.size()
            if size > TextComparison.ByteLimit do
                fail Errors.InvalidFormatError{}
            bytes[index].resize(size)
            bytes[index].resize(try stream.read(bytes[index].toSlice()))
        }

        if .kind == .Binary
        {
            .text.compareBytes(bytes[0].toSlice(), bytes[1].toSlice())
            return
        }

        var decoded: [2] String
        for index in 2
        {
            let source   = bytes[index].toSlice()
            let encoding = Text.detectEncoding(source)
            let bom      = Text.hasBom(source, encoding) ? Text.bomLength(encoding) : 0
            decoded[index] = Text.decode(source[bom to], encoding)
        }

        .text.compare(decoded[0], decoded[1], .options)
    }
}
