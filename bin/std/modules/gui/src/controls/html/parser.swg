#global internal

using Core

// Feeds source bytes into an [[HtmlDocument]], one chunk at a time.
//
// The parser is resumable: `feed` consumes every complete token it can see and keeps the
// unfinished tail, so a document read from disk in fixed-size chunks produces exactly the tree
// the whole file would. `finish` flushes that tail, closing whatever the source left open.
#[Swag.NoDoc]
public struct HtmlParser
{
    #[Swag.Late]
    document: *HtmlDocument

    stack:      Array'u32
    carry:      String
    baseOffset: u64
    rawTag:     HtmlTag
    inRawText:  bool
    done:       bool
}

impl HtmlParser
{
    // Binds a parser to the document it fills, which must outlive it.
    mtd start(document: *HtmlDocument)
    {
        .document = document
        .stack.clear()
        .stack.add(0)
        .carry.clear()
        .baseOffset = 0
        .inRawText  = false
        .done       = false
    }

    mtd current()->u32 => .stack.back()

    // Reports whether an element with that tag is open, so a stray end tag closes nothing.
    mtd const isOpen(tag: HtmlTag)->bool
    {
        for element in .stack where .document.constNode(element).tag == tag do
            return true
        return false
    }

    mtd popTo(tag: HtmlTag)
    {
        while .stack.count > 1
        {
            let closed = .document.constNode(.stack.back()).tag
            .stack.removeBack()
            if closed == tag do
                return
        }
    }

    // Closes the elements an HTML author is allowed to leave open before `tag` starts.
    //
    // A paragraph ends where the next block begins, a list item ends where the next one begins,
    // and a table cell ends at the next cell or row. Without this an unbalanced page nests every
    // following block one level deeper until the document is one long staircase.
    mtd closeImplied(tag: HtmlTag)
    {
        while .stack.count > 1
        {
            let open = .document.constNode(.stack.back()).tag
            var close: bool
            switch open
            {
            case .P:                     close = HtmlParser.startsBlock(tag)
            case .Li:                    close = tag == .Li
            case .Dt, .Dd:               close = tag == .Dt or tag == .Dd
            case .Option:                close = tag == .Option or tag == .OptGroup
            case .Td, .Th:               close = tag == .Td or tag == .Th or tag == .Tr or tag == .TBody or tag == .THead or tag == .TFoot
            case .Tr:                    close = tag == .Tr or tag == .TBody or tag == .THead or tag == .TFoot
            case .TBody, .THead, .TFoot: close = tag == .TBody or tag == .THead or tag == .TFoot
            case .Head:                  close = tag == .Body
            case .A:                     close = tag == .A
            }

            if !close do
                return
            .stack.removeBack()
        }
    }

    // Reports whether an element interrupts an open paragraph.
    func startsBlock(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .Address, .Article, .Aside, .Blockquote, .Details, .Div, .Dl, .Dt, .Dd, .FieldSet,
             .FigCaption, .Figure, .Footer, .Form, .H1, .H2, .H3, .H4, .H5, .H6, .Header, .HGroup,
             .Hr, .Li, .Main, .Menu, .Nav, .Ol, .P, .Pre, .Section, .Summary, .Table, .Ul: return true
        }

        return false
    }

    // Appends decoded text, ignoring a run that is only whitespace outside any element.
    //
    // Text arriving in several pieces joins the node the previous piece produced, so a document
    // read in chunks yields exactly the tree the whole source yields.
    mtd emitText(text: string, offset: u64)
    {
        if !@countof(text) do
            return
        if .stack.count == 1 and !@countof(Latin1.trim(text)) do
            return
        .document.appendText(.current(), htmlDecodeText(text).toString(), offset)
    }

    // Emits raw element content verbatim, because a script or a stylesheet carries no markup.
    mtd emitRawText(text: string, offset: u64)
    {
        if !@countof(text) do
            return
        .document.appendText(.current(), text, offset)
    }

    // Reads the attributes of a start tag, whose text spans from just after the element name to
    // just before the closing `>`.
    mtd readAttributes(element: u32, tag: string)
    {
        var index = 0'u64
        while index < @countof(tag)
        {
            while index < @countof(tag) and Latin1.isSpace(tag[index]) do
                index += 1
            if index >= @countof(tag) do
                return

            let nameStart = index
            while index < @countof(tag) and !Latin1.isSpace(tag[index]) and tag[index] != '=' and tag[index] != '/' do
                index += 1
            if index == nameStart
            {
                index += 1
                continue
            }

            let name = String.from(tag[nameStart until index]).toLower()
            while index < @countof(tag) and Latin1.isSpace(tag[index]) do
                index += 1
            if index >= @countof(tag) or tag[index] != '='
            {
                .document.addAttribute(element, name.toString(), "")
                continue
            }

            index += 1
            while index < @countof(tag) and Latin1.isSpace(tag[index]) do
                index += 1
            if index >= @countof(tag)
            {
                .document.addAttribute(element, name.toString(), "")
                return
            }

            var valueStart = index
            var valueEnd   = index
            let quote      = tag[index]
            if quote == '"' or quote == '\''
            {
                valueStart = index + 1
                valueEnd   = valueStart
                while valueEnd < @countof(tag) and tag[valueEnd] != quote do
                    valueEnd += 1
                index = Math.min(valueEnd + 1, @countof(tag))
            }
            else
            {
                while valueEnd < @countof(tag) and !Latin1.isSpace(tag[valueEnd]) do
                    valueEnd += 1
                index = valueEnd
            }

            .document.addAttribute(element, name.toString(), htmlDecodeText(tag[valueStart until valueEnd]).toString())
        }
    }

    mtd openElement(name: string, tag: string, offset: u64)
    {
        let interned = HtmlDocument.tagFromName(name)
        .closeImplied(interned)

        let element = .document.addElement(.current(), name, offset)
        let nameEnd = Math.min(@countof(name), @countof(tag))
        .readAttributes(element, tag[nameEnd to])

        let selfClosing = @countof(tag) and tag[@countof(tag) - 1] == '/'
        if HtmlDocument.isVoidTag(interned) or selfClosing do
            return

        .stack.add(element)
        if HtmlDocument.isRawTextTag(interned)
        {
            .inRawText = true
            .rawTag    = interned
        }
    }

    mtd closeElement(name: string)
    {
        let interned = HtmlDocument.tagFromName(name)
        if HtmlDocument.isVoidTag(interned) do
            return
        if interned == .Unknown
        {
            for index in .stack.count where .document.constNode(.stack[index]).name == name
            {
                .stack.resize(index)
                return
            }

            return
        }

        if !.isOpen(interned) do
            return
        .popTo(interned)
    }

    // Consumes `<`-introduced markup at `index`, returning the position just after it.
    //
    // Returns `Swag.U64.Max` when the token is cut by the end of the buffer and the caller must
    // wait for more source.
    mtd readMarkup(source: string, index: u64)->u64
    {
        let remaining = source[index to]
        if Utf8.startsWith(remaining, "<!--")
        {
            let end = Utf8.indexOf(source, "-->", index + 4)
            return end == Swag.U64.Max ? Swag.U64.Max : end + 3
        }

        // A conditional-comment style declaration and a doctype both end at the first `>`.
        if Utf8.startsWith(remaining, "<!") or Utf8.startsWith(remaining, "<?")
        {
            let end = Utf8.indexOf(source, '>'rune, index + 2)
            return end == Swag.U64.Max ? Swag.U64.Max : end + 1
        }

        let close = Utf8.indexOf(source, '>'rune, index + 1)
        if close == Swag.U64.Max do
            return Swag.U64.Max

        let tag = source[index + 1 until close]
        if !@countof(tag) do
            return close + 1

        if tag[0] == '/'
        {
            var nameEnd = 1'u64
            while nameEnd < @countof(tag) and !Latin1.isSpace(tag[nameEnd]) do
                nameEnd += 1
            .closeElement(String.from(tag[1 until nameEnd]).toLower().toString())
            return close + 1
        }

        var nameEnd = 0'u64
        while nameEnd < @countof(tag) and !Latin1.isSpace(tag[nameEnd]) and tag[nameEnd] != '/' do
            nameEnd += 1
        if !nameEnd do
            return close + 1

        let name = String.from(tag[0 until nameEnd]).toLower()
        .openElement(name.toString(), tag, .baseOffset + index)
        return close + 1
    }

    // Consumes the body of a raw-text element, which ends only at its own end tag.
    mtd readRawText(source: string, index: u64)->u64
    {
        let closing = Format.toString("</%", .document.constNode(.current()).name.toString())
        let end     = Utf8.indexOf(source, closing.toString(), index, .Latin1NoCase)
        if end == Swag.U64.Max do
            return Swag.U64.Max

        let close = Utf8.indexOf(source, '>'rune, end)
        if close == Swag.U64.Max do
            return Swag.U64.Max

        .emitRawText(source[index until end], .baseOffset + index)
        .inRawText = false
        .stack.removeBack()
        return close + 1
    }

    // Returns the position from which the buffer must be kept for the next chunk.
    //
    // Text is safe to emit up to the last byte that cannot start a cut token: an unterminated
    // `<` or a character reference whose `;` may still be coming.
    func safeTextEnd(text: string)->u64
    {
        const MaxEntityLength = 32'u64

        var scan = @countof(text)
        let stop = @countof(text) > MaxEntityLength ? @countof(text) - MaxEntityLength : 0
        while scan > stop
        {
            scan -= 1
            if text[scan] == '&' do
                return scan
            if text[scan] == ';' do
                break
        }

        return @countof(text)
    }

    // Parses everything `chunk` completes, keeping the rest for the next call.
    mtd feed(chunk: string)
    {
        .carry += chunk
        .parseCarry(false)
    }

    // Parses what remains and closes every element the source left open.
    mtd finish()
    {
        .parseCarry(true)
        .carry.clear()
        while .stack.count > 1 do
            .stack.removeBack()
        .done = true
    }

    private mtd parseCarry(final: bool)
    {
        let source = .carry.toString()
        var index  = 0'u64
        var kept   = 0'u64

        while index < @countof(source)
        {
            if .inRawText
            {
                let next = .readRawText(source, index)
                if next == Swag.U64.Max
                {
                    if !final do
                        break

                    .emitRawText(source[index to], .baseOffset + index)
                    .inRawText = false
                    .stack.removeBack()
                    index = @countof(source)
                    break
                }

                index = next
                kept  = index
                continue
            }

            if source[index] == '<'
            {
                let next = .readMarkup(source, index)
                if next == Swag.U64.Max
                {
                    if !final do
                        break
                    index = @countof(source)
                    break
                }

                index = next
                kept  = index
                continue
            }

            var end = Utf8.indexOf(source, '<'rune, index)
            if end == Swag.U64.Max do
                end = @countof(source)

            var text = source[index until end]
            if !final and end == @countof(source)
            {
                let safe = HtmlParser.safeTextEnd(text)
                text = text[0 until safe]
                .emitText(text, .baseOffset + index)
                index += safe
                kept  = index
                break
            }

            .emitText(text, .baseOffset + index)
            index = end
            kept  = index
        }

        if final do
            kept = @countof(source)
        if !kept do
            return

        .baseOffset += kept
        var remaining = String.from(source[kept to])
        .carry = #move remaining
    }
}
