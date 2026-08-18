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

    stack:       Array'u32
    carry:       String
    baseOffset:  u64
    rawTag:      HtmlTag
    inRawText:   bool
    dropNewline: bool
    done:        bool
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
        .baseOffset  = 0
        .inRawText   = false
        .dropNewline = false
        .done        = false
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

    // Reports whether an implicitly closable element ends where `tag` starts.
    //
    // A paragraph ends where the next block begins, a list item ends where the next one begins,
    // and a table cell ends at the next cell or row. Without this an unbalanced page nests every
    // following block one level deeper until the document is one long staircase.
    func impliedCloses(open, tag: HtmlTag)->bool
    {
        switch open
        {
        case .P:                     return HtmlParser.startsBlock(tag)
        case .Li:                    return tag == .Li
        case .Dt, .Dd:               return tag == .Dt or tag == .Dd
        case .Option:                return tag == .Option or tag == .OptGroup
        case .Td, .Th:               return tag == .Td or tag == .Th or tag == .Tr or tag == .TBody or tag == .THead or tag == .TFoot
        case .Tr:                    return tag == .Tr or tag == .TBody or tag == .THead or tag == .TFoot
        case .TBody, .THead, .TFoot: return tag == .TBody or tag == .THead or tag == .TFoot
        case .Head:                  return tag == .Body
        case .A:                     return tag == .A
        }

        return false
    }

    // Reports whether an open element lets an implied close look past it. Phrasing content never
    // keeps a paragraph or a list item alive on its own; a block or a form control does.
    func looksThroughImpliedClose(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .A, .Abbr, .B, .Cite, .Code, .Del, .Dfn, .Em, .I, .Ins, .Kbd, .Label, .Mark, .Output, .Q,
             .Rp, .Rt, .Ruby, .S, .Samp, .Small, .Span, .Strong, .Sub, .Sup, .Time, .U, .Var: return true
        }

        return false
    }

    // Closes the elements an HTML author is allowed to leave open before `tag` starts.
    mtd closeImplied(tag: HtmlTag)
    {
        while .stack.count > 1
        {
            // The element this start tag closes is not always on top: a paragraph interrupted
            // while an inline element is open still ends, and its open inlines end with it.
            var depth = .stack.count
            var found = 0'u64
            while depth > 1
            {
                let open = .document.constNode(.stack[depth - 1]).tag
                if HtmlParser.impliedCloses(open, tag)
                {
                    found = depth - 1
                    break
                }

                if !HtmlParser.looksThroughImpliedClose(open) do
                    return
                depth -= 1
            }

            if !found do
                return
            .stack.resize(found)
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

    // Returns how many bytes to skip when the HTML rules discard the newline that immediately
    // follows a `<pre>` or `<textarea>` start tag. The pending drop is consumed whatever the
    // first content turns out to be, because the rule only ever applies to the very next token.
    mtd eatDroppedNewline(text: string)->u64
    {
        if !.dropNewline do
            return 0
        .dropNewline = false
        if text[0] == '\r' do
            return @countof(text) > 1 and text[1] == '\n' ? 2 : 1
        return text[0] == '\n' ? 1 : 0
    }

    // Appends decoded text, ignoring a run that is only whitespace outside any element.
    //
    // Text arriving in several pieces joins the node the previous piece produced, so a document
    // read in chunks yields exactly the tree the whole source yields.
    mtd emitText(text: string, offset: u64)
    {
        if !@countof(text) do
            return

        let eat     = .eatDroppedNewline(text)
        let content = text[eat to]
        if !@countof(content) do
            return
        if .stack.count == 1 and !@countof(Latin1.trim(content)) do
            return

        // Only genuine content is fostered out of the table structure. The whitespace between
        // rows stays where the source put it — unless a fostered run already sits in front of
        // the table, where a chunk edge may have isolated one of the run's own spaces.
        var anchor = .fosterAnchor()
        if anchor != HtmlNoNode and !@countof(Latin1.trim(content)) and !.document.precededByText(anchor) do
            anchor = HtmlNoNode
        if anchor != HtmlNoNode
        {
            .document.insertTextBefore(anchor, htmlDecodeText(content).toString(), offset + eat)
            return
        }

        .document.appendText(.current(), htmlDecodeText(content).toString(), offset + eat)
    }

    // Emits raw element content verbatim, because a script or a stylesheet carries no markup.
    mtd emitRawText(text: string, offset: u64)
    {
        if !@countof(text) do
            return

        let eat     = .eatDroppedNewline(text)
        let content = text[eat to]
        if !@countof(content) do
            return
        .document.appendText(.current(), content, offset + eat)
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

    // Reports whether the table structure takes this child where it stands. Anything else is
    // foster-parented in front of the table, which is where browsers put it.
    func tableAccepts(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .Caption, .ColGroup, .Col, .TBody, .THead, .TFoot, .Tr, .Td, .Th, .Script, .Style, .Template, .Form: return true
        }

        return false
    }

    // Returns the table to insert in front of when the insertion point sits in the table
    // structure between cells, `HtmlNoNode` when content belongs where it is.
    mtd const fosterAnchor()->u32
    {
        let parent = .document.constNode(.stack.back()).tag
        let inTableStructure = parent == .Table or parent == .TBody or parent == .THead or parent == .TFoot or parent == .Tr
        if !inTableStructure do
            return HtmlNoNode

        var depth = .stack.count
        while depth > 1
        {
            let element = .stack[depth - 1]
            if .document.constNode(element).tag == .Table do
                return element
            depth -= 1
        }

        return HtmlNoNode
    }

    mtd openElement(name: string, tag: string, offset: u64)
    {
        let interned = HtmlDocument.tagFromName(name)
        .closeImplied(interned)

        // Content the table structure does not accept renders in front of the table, not
        // inside the grid.
        var element: u32
        let anchor = HtmlParser.tableAccepts(interned) ? HtmlNoNode : .fosterAnchor()
        if anchor != HtmlNoNode do
            element = .document.insertElementBefore(anchor, name, offset)
        else do
            element = .document.addElement(.current(), name, offset)

        let nameEnd = Math.min(@countof(name), @countof(tag))
        .readAttributes(element, tag[nameEnd to])

        let selfClosing = @countof(tag) and tag[@countof(tag) - 1] == '/'
        if HtmlDocument.isVoidTag(interned) or selfClosing do
            return

        .stack.add(element)

        // The newline immediately following the start tag of these two elements is not content,
        // which is what lets an author put the tag on a line of its own.
        if interned == .Pre or interned == .TextArea do
            .dropNewline = true

        if HtmlDocument.isRawTextTag(interned)
        {
            .inRawText = true
            .rawTag    = interned
        }
    }

    // The elements whose formatting survives misnesting, per the HTML standard's list of
    // formatting elements this engine knows.
    func isFormattingTag(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .A, .B, .Code, .Em, .I, .S, .Small, .Strong, .U: return true
        }

        return false
    }

    mtd closeElement(name: string, offset: u64)
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

        // Misnested formatting keeps its formatting: the formatting elements this close pops
        // along with its target reopen as fresh elements, which is the visible result of the
        // adoption agency the standard specifies. A cell, a caption, and a template bound the
        // formatting scope and reopen nothing.
        var reopen: Array'u32
        if interned != .Td and interned != .Th and interned != .Caption and interned != .Template
        {
            var depth = .stack.count
            while depth > 1 and .document.constNode(.stack[depth - 1]).tag != interned
            {
                reopen.add(.stack[depth - 1])
                depth -= 1
            }

            for element in reopen where !HtmlParser.isFormattingTag(.document.constNode(element).tag)
            {
                reopen.clear()
                break
            }
        }

        .popTo(interned)

        // Reopened bottom-up, so the clones nest in their original order. The names and
        // attributes are copied out first: adding an element may reallocate the node storage.
        while reopen.count
        {
            let source = reopen.back()
            reopen.removeBack()

            var cloneName:       String              = .document.constNode(source).name
            var cloneAttributes: Array'HtmlAttribute = .document.constNode(source).attributes
            let clone = .document.addElement(.current(), cloneName.toString(), offset)
            for attribute in cloneAttributes do
                .document.addAttribute(clone, attribute.name.toString(), attribute.value.toString())
            .stack.add(clone)
        }
    }

    // Finds the `>` that ends a tag, skipping the ones inside quoted attribute values, which is
    // where a title or a data attribute legitimately carries the character. A quote only opens a
    // value after `=`, so a stray one in a malformed tag cannot swallow the document.
    func findTagEnd(source: string, start: u64)->u64
    {
        var scan   = start
        var quote  = 0'u8
        var equals = false
        while scan < @countof(source)
        {
            let character = source[scan]
            if quote
            {
                if character == quote do
                    quote = 0
            }
            elif (character == '"' or character == '\'') and equals
            {
                quote  = character
                equals = false
            }
            elif character == '>'
            {
                return scan
            }
            elif character == '='
            {
                equals = true
            }
            elif !Latin1.isSpace(character)
            {
                equals = false
            }

            scan += 1
        }

        return Swag.U64.Max
    }

    // Consumes `<`-introduced markup at `index`, returning the position just after it.
    //
    // Returns `Swag.U64.Max` when the token is cut by the end of the buffer and the caller must
    // wait for more source.
    mtd readMarkup(source: string, index: u64)->u64
    {
        // Whatever this markup turns out to be, it is the token that follows the previous one,
        // so a pending newline drop expires here.
        .dropNewline = false

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

        let close = HtmlParser.findTagEnd(source, index + 1)
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
            .closeElement(String.from(tag[1 until nameEnd]).toLower().toString(), .baseOffset + index)
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
