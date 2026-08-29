#global internal

using Core

// The deepest element nesting the tree keeps. Styling, box building and painting all recurse
// per element depth, so an unbounded depth would let a few hundred kilobytes of nothing but
// `<div>` walk the native stack to overflow; past the bound, new elements are flattened into
// their deepest kept ancestor and the document stays readable.
const HtmlMaxElementDepth = 256'u64

// What ends a run of text: the markup that follows it, or the reference that makes it need
// decoding. Both are looked for in the same pass.
const HtmlTextStops: [2] u8 = ['<'u8, '&'u8]

// One element the parser has opened and not yet closed.
//
// The tag travels with the index because the stack is walked several times per source tag — for
// implied closes, for the foster anchor, for a stray end tag — and reading it back from the node
// array costs a cache miss into a structure that is two orders of magnitude larger than the
// stack itself.
//
// It travels with [[Gui.HtmlView]], which carries the parser as a field.
#[Swag.NoDoc]
public struct HtmlOpenElement
{
    element: u32
    tag:     HtmlTag
}

// One attribute read from a start tag, as runs of the buffer being parsed.
//
// A tag is read in one pass, but the element it opens only exists once the `>` that ends it is in
// the buffer: what the pass finds waits here rather than in the document.
#[Swag.NoDoc]
public struct HtmlPendingAttribute
{
    name:         HtmlRange
    value:        HtmlRange
    hasValue:     bool
    hasUpper:     bool
    hasReference: bool
}

// Where a start tag ends, and what its name is.
#[Swag.NoDoc]
public struct HtmlTagScan
{
    nameStart:   u32
    nameEnd:     u32
    selfClosing: bool
    hasUpper:    bool
    end       = Swag.U64.Max
}

// What a source is parsed as.
//
// A document carries the `html`, `head` and `body` elements even when it writes none of them, and
// a page's `body { ... }` rules only mean anything because of that. A fragment is content parsed
// for a place that already exists — the raw HTML block of a Markdown document, for one — where
// those elements would add a page's margins inside somebody else's box.
#[Swag.NoDoc]
public enum HtmlParserMode
{
    Document
    Fragment
}

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

    stack:       Array'HtmlOpenElement
    pending:     Array'HtmlPendingAttribute

    // Where the tokenizer stands inside the source the document keeps. Text is addressed there
    // rather than copied out of it, so a run of a page's content costs two numbers.
    parseIndex:  u64
    baseOffset:  u64
    rawTag:      HtmlTag
    mode:        HtmlParserMode
    inRawText:   bool
    dropNewline: bool
    done:        bool
    depthCapped: bool

    // The elements the parsing model implies, whether the source wrote them or not.
    htmlElement = HtmlNoNode
    headElement = HtmlNoNode
    bodyElement = HtmlNoNode
}

impl HtmlParser
{
    // Binds a parser to the document it fills, which must outlive it.
    mtd start(document: *HtmlDocument, mode = HtmlParserMode.Document)
    {
        .document = document
        .stack.clear()
        .stack.add({0, HtmlTag.Unknown})
        .parseIndex  = 0
        .mode        = mode
        .baseOffset  = 0
        .inRawText   = false
        .dropNewline = false
        .done        = false
        .depthCapped = false
        .htmlElement = HtmlNoNode
        .headElement = HtmlNoNode
        .bodyElement = HtmlNoNode
    }

    // Reports whether the insertion point is still outside the two sections of a document, which
    // is where content decides which of them it belongs to.
    mtd const atDocumentLevel()->bool
    {
        let tag = .stack.back().tag
        return .stack.count == 1 or tag == .Html
    }

    // Opens the element a document implies, and returns it.
    mtd openImplied(tag: HtmlTag, offset: u64)->u32
    {
        var implied: HtmlRange
        let element = .document.addElement(.current(), implied, tag, offset)
        .stack.add({element, tag})
        return element
    }

    // Makes sure the `html` element exists and is the insertion point's ancestor.
    mtd ensureHtml(offset: u64)
    {
        if .htmlElement != HtmlNoNode
        {
            if !.isOpen(.Html) do
                .stack.add({.htmlElement, HtmlTag.Html})
            return
        }

        while .stack.count > 1 do
            .stack.removeBack()
        .htmlElement = .openImplied(.Html, offset)
    }

    // Makes sure the `head` element exists and is open.
    mtd ensureHead(offset: u64)
    {
        .ensureHtml(offset)
        if .headElement != HtmlNoNode
        {
            if !.isOpen(.Head) do
                .stack.add({.headElement, HtmlTag.Head})
            return
        }

        .headElement = .openImplied(.Head, offset)
    }

    // Makes sure the `body` element exists and is open, closing the head it follows.
    //
    // Content written after `</body>` returns to the same body, which is what a browser does with
    // it rather than starting a second one.
    mtd ensureBody(offset: u64)
    {
        .ensureHtml(offset)
        if .isOpen(.Head) do
            .popTo(.Head)
        if .bodyElement != HtmlNoNode
        {
            if !.isOpen(.Body) do
                .stack.add({.bodyElement, HtmlTag.Body})
            return
        }

        .bodyElement = .openImplied(.Body, offset)
    }

    // Reports whether an element belongs to the head of a document rather than to its body.
    func belongsToHead(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .Base, .Link, .Meta, .Title, .Style, .Script, .NoScript, .Template: return true
        }

        return false
    }

    // Takes a written `html`, `head` or `body` start tag as the one the document already has, and
    // reports whether it was consumed here.
    //
    // A source that writes them is the same document as one that does not: the second `<body>` a
    // malformed page opens carries its attributes into the first, rather than starting a section
    // that nothing styles.
    mtd adoptWrittenSection(tag: HtmlTag, source: string, offset: u64)->bool
    {
        switch tag
        {
        case .Html:
            .ensureHtml(offset)
            .readSectionAttributes(.htmlElement, source)
            return true

        case .Head:
            .ensureHead(offset)
            .readSectionAttributes(.headElement, source)
            return true

        case .Body:
            .ensureBody(offset)
            .readSectionAttributes(.bodyElement, source)
            return true
        }

        return false
    }

    // Reads a section's attributes while they can still extend that element's run of the pool.
    //
    // A page that opens `<body>` a second time around its content keeps the first spelling: the
    // standard merges the attributes it does not already carry, and the half that matters — the
    // first `<body class=...>` wins — is what this keeps.
    mtd readSectionAttributes(element: u32, source: string)
    {
        let range = .document.constNode(element).attributes
        if range.start + range.count != cast(u32) .document.attributePool.count do
            return
        .flushAttributes(element, source)
    }

    // Opens the section a start tag belongs to, before the element itself is inserted.
    mtd openImpliedSection(tag: HtmlTag, offset: u64)
    {
        if .mode == .Fragment do
            return

        let inHead = .stack.back().tag == .Head
        if !.atDocumentLevel() and !inHead do
            return

        // Head content stays in the head until something that belongs to the body has started
        // one; after that the head is closed and a stray `<style>` renders where it was written.
        if HtmlParser.belongsToHead(tag) and .bodyElement == HtmlNoNode
        {
            if !inHead do
                .ensureHead(offset)
            return
        }

        .ensureBody(offset)
    }

    mtd current()->u32 => .stack.back().element

    // Reports whether an element with that tag is open, so a stray end tag closes nothing.
    mtd const isOpen(tag: HtmlTag)->bool
    {
        for open in .stack where open.tag == tag do
            return true
        return false
    }

    mtd popTo(tag: HtmlTag)
    {
        while .stack.count > 1
        {
            let closed = .stack.back().tag
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
                let open = .stack[depth - 1].tag
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
    mtd emitText(text: string, hasReference: bool, offset: u64)
    {
        if !@countof(text) do
            return

        let eat     = .eatDroppedNewline(text)
        let content = text[eat to]
        if !@countof(content) do
            return

        // Whitespace between the sections of a document is not content; anything else there is
        // what starts the body.
        if .mode == .Document and (.atDocumentLevel() or .stack.back().tag == .Head)
        {
            if !@countof(Latin1.trim(content)) do
                return
            .ensureBody(offset + eat)
        }
        elif .stack.count == 1 and !@countof(Latin1.trim(content))
        {
            return
        }

        // Only genuine content is fostered out of the table structure. The whitespace between
        // rows stays where the source put it — unless a fostered run already sits in front of
        // the table, where a chunk edge may have isolated one of the run's own spaces.
        var anchor = .fosterAnchor()
        if anchor != HtmlNoNode and !@countof(Latin1.trim(content)) and !.document.precededByText(anchor) do
            anchor = HtmlNoNode
        let decoded = .internText(content, hasReference)
        if anchor != HtmlNoNode
        {
            .document.insertTextBefore(anchor, decoded, offset + eat)
            return
        }

        .document.appendText(.current(), decoded, offset + eat)
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

        .document.appendText(.current(), HtmlDocument.sourceRange(.sourceStart(content), @countof(content)), offset + eat)
    }

    // Reads a tag from just after its `<` (and its `/` for an end tag) to the `>` that ends it.
    //
    // One pass answers everything the tree builder needs: where the name is, whether the source
    // wrote it in mixed case, whether the tag closes itself, and every attribute — kept as runs of
    // the buffer, because the element they belong to does not exist yet. A quoted value is skipped
    // whole by the vectorized search for its closing quote rather than a byte at a time.
    //
    // `end` stays `Swag.U64.Max` when the buffer cuts the tag, and the caller waits for more.
    mtd scanTag(source: string, start: u64)->HtmlTagScan
    {
        var result: retval
        .pending.clear()

        let count = @countof(source)
        var index = start

        result.nameStart = cast(u32) index
        while index < count
        {
            let character = source[index]
            if Latin1.isSpace(character) or character == '/' or character == '>' do
                break
            if Latin1.isUpper(character) do
                result.hasUpper = true
            index += 1
        }

        result.nameEnd = cast(u32) index

        while index < count
        {
            let character = source[index]
            if character == '>'
            {
                result.end = index
                return result
            }

            if character == '/'
            {
                // A `/` closes the tag only where the standard says it does: right before the `>`.
                index += 1
                if index < count and source[index] == '>'
                {
                    result.selfClosing = true
                    result.end         = index
                }

                continue
            }

            if Latin1.isSpace(character)
            {
                index += 1
                continue
            }

            var attribute: HtmlPendingAttribute
            let nameStart = index
            while index < count
            {
                let letter = source[index]
                if Latin1.isSpace(letter) or letter == '=' or letter == '/' or letter == '>' do
                    break
                if Latin1.isUpper(letter) do
                    attribute.hasUpper = true
                index += 1
            }

            attribute.name = {cast(u32) nameStart, cast(u32) (index - nameStart)}

            while index < count and Latin1.isSpace(source[index]) do
                index += 1
            if index >= count do
                return result
            if source[index] != '='
            {
                .pending.add(attribute)
                continue
            }

            index += 1
            while index < count and Latin1.isSpace(source[index]) do
                index += 1
            if index >= count do
                return result

            let quote = source[index]
            if quote == '"' or quote == '\''
            {
                let valueStart = index + 1
                var stops: [2] u8 = [quote, '&'u8]
                var closing       = valueStart
                while true
                {
                    let next = Utf8.indexOfAny(source, @mkslice(&stops[0], 2), closing)
                    if next == Swag.U64.Max do
                        return result
                    if source[next] == quote
                    {
                        closing = next
                        break
                    }

                    attribute.hasReference = true
                    closing                = next + 1
                }

                attribute.value = {cast(u32) valueStart, cast(u32) (closing - valueStart)}
                index           = closing + 1
            }
            else
            {
                let valueStart = index
                while index < count and !Latin1.isSpace(source[index]) and source[index] != '>'
                {
                    if source[index] == '&' do
                        attribute.hasReference = true
                    index += 1
                }

                attribute.value = {cast(u32) valueStart, cast(u32) (index - valueStart)}
            }

            attribute.hasValue = true
            .pending.add(attribute)
        }

        return result
    }

    // Hands an element the attributes the tag scan found.
    mtd flushAttributes(element: u32, source: string)
    {
        for attribute in .pending
        {
            let raw  = source[attribute.name.start until attribute.name.start + attribute.name.count]
            let name = attribute.hasUpper ? .document.internLower(raw) : HtmlDocument.sourceRange(.sourceStart(raw), attribute.name.count)
            var value: HtmlRange
            if attribute.hasValue
            {
                let text = source[attribute.value.start until attribute.value.start + attribute.value.count]
                value = .internText(text, attribute.hasReference, true)
            }

            .document.addAttribute(element, name, value)
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
        let parent           = .stack.back().tag
        let inTableStructure = parent == .Table or parent == .TBody or parent == .THead or parent == .TFoot or parent == .Tr
        if !inTableStructure do
            return HtmlNoNode

        var depth = .stack.count
        while depth > 1
        {
            let open = .stack[depth - 1]
            if open.tag == .Table do
                return open.element
            depth -= 1
        }

        return HtmlNoNode
    }

    // Opens an element from its folded name and what the tag scan found.
    mtd openElement(name: string, fromSource: bool, source: string, scan: HtmlTagScan, offset: u64)
    {
        let interned = HtmlDocument.tagFromName(name)

        // A document writes `html`, `head` and `body` or leaves them implied; either way the tree
        // carries them, which is what makes a page's own `body { ... }` rules mean something.
        if .mode == .Document and .adoptWrittenSection(interned, source, offset) do
            return

        .openImpliedSection(interned, offset)
        .closeImplied(interned)

        // Content the table structure does not accept renders in front of the table, not
        // inside the grid.
        // Only a tag this engine does not know has to remember how it was spelled, and it can do
        // that by addressing the source unless the name had to be folded.
        var spelling: HtmlRange
        if interned == .Unknown do
            spelling = fromSource ? HtmlDocument.sourceRange(.sourceStart(name), @countof(name)) : .document.intern(name)

        var element: u32
        let anchor = HtmlParser.tableAccepts(interned) ? HtmlNoNode : .fosterAnchor()
        if anchor != HtmlNoNode do
            element = .document.insertElementBefore(anchor, spelling, interned, offset)
        else do
            element = .document.addElement(.current(), spelling, interned, offset)

        .flushAttributes(element, source)

        if HtmlDocument.isVoidTag(interned) or scan.selfClosing do
            return

        // Past the depth bound the element stays in the tree as a leaf and its content lands in
        // the deepest kept ancestor, so a hostile nesting flattens instead of overflowing the
        // recursive passes downstream.
        if .stack.count >= HtmlMaxElementDepth
        {
            .depthCapped = true
            return
        }

        .stack.add({element, interned})

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

    // Closes an element from the raw name the source wrote, which the tree keeps folded to lower
    // case. Folding is what would cost an allocation, so it happens only for the rare end tag
    // that is not already written in lower case.
    mtd closeElement(rawName: string, rawHasUpper: bool, offset: u64)
    {
        var folded: String
        var name = rawName
        if rawHasUpper
        {
            folded = String.toLower(rawName)
            name   = folded.toString()
        }

        // A well-formed document closes what it last opened, and that element already knows its
        // tag: one comparison then answers what resolving the name costs a comparison per known
        // tag to answer.
        var interned = .stack.count > 1 and name == .document.name(.stack.back().element) ? .stack.back().tag : HtmlDocument.tagFromName(name)
        if HtmlDocument.isVoidTag(interned) do
            return
        if interned == .Unknown
        {
            for index in .stack.count where .document.name(.stack[index].element) == name
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
        var reopen: Array'HtmlOpenElement
        if interned != .Td and interned != .Th and interned != .Caption and interned != .Template
        {
            var depth = .stack.count
            while depth > 1 and .stack[depth - 1].tag != interned
            {
                reopen.add(.stack[depth - 1])
                depth -= 1
            }

            for open in reopen where !HtmlParser.isFormattingTag(open.tag)
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

            // Only a known formatting element ever reopens, so the clone's name comes from its
            // tag; its attributes are copied out first, because adding an element may reallocate
            // the pool they live in, and they point at text the original already interned.
            var cloneAttributes: Array'HtmlAttribute
            cloneAttributes.add(.document.attributes(source.element))
            var cloneName: HtmlRange
            let clone = .document.addElement(.current(), cloneName, source.tag, offset)
            for attribute in cloneAttributes do
                .document.addAttribute(clone, attribute.name, attribute.value)

            .stack.add({clone, source.tag})
        }
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

        var nameStart = index + 1
        let closing   = nameStart < @countof(source) and source[nameStart] == '/'
        if closing do
            nameStart += 1

        let scan = .scanTag(source, nameStart)
        if scan.end == Swag.U64.Max do
            return Swag.U64.Max
        if scan.nameEnd == scan.nameStart do
            return scan.end + 1

        let raw = source[scan.nameStart until scan.nameEnd]
        if closing
        {
            .closeElement(raw, scan.hasUpper, index)
            return scan.end + 1
        }

        var folded: String
        var name = raw
        if scan.hasUpper
        {
            folded = String.toLower(raw)
            name   = folded.toString()
        }

        .openElement(name, !scan.hasUpper, source, scan, index)
        return scan.end + 1
    }

    // Consumes the body of a raw-text element, which ends only at its own end tag.
    mtd readRawText(source: string, index: u64)->u64
    {
        let closing = Format.toString("</%", HtmlDocument.tagName(.rawTag))
        let end     = Utf8.indexOf(source, closing.toString(), index, .Latin1NoCase)
        if end == Swag.U64.Max do
            return Swag.U64.Max

        let close = Utf8.indexOf(source, '>'rune, end)
        if close == Swag.U64.Max do
            return Swag.U64.Max

        .emitRawText(source[index until end], index)
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

    // Returns where a slice of the source starts inside it.
    //
    // Every run the parser hands the document is a stretch of the very bytes the document keeps,
    // so its offset is the difference between the two pointers.
    mtd const sourceStart(text: string)->u64 => cast(u64) (@dataof(text) - @dataof(.document.source()))

    // Returns the run `text` occupies, decoding it only when it carries a character reference.
    //
    // This is where a page's text stops being copied: the scan that looked for the `<` ending the
    // run also looked for the `&` that would make it need rewriting, so an entity-free run — which
    // is nearly all of them — becomes two numbers and no bytes at all.
    mtd internText(text: string, hasReference: bool, inAttribute = false)->HtmlRange
    {
        if !hasReference do
            return HtmlDocument.sourceRange(.sourceStart(text), @countof(text))
        return .document.internDecoded(text, inAttribute)
    }

    // Reports whether the parser is holding source it could not finish reading.
    mtd const hasPendingSource()->bool => .parseIndex < @countof(.document.source())

    // Parses everything `chunk` completes, keeping the rest for the next call.
    mtd feed(chunk: string)
    {
        discard .document.appendSource(chunk)
        .parseSource(false)
    }

    // Parses what remains and closes every element the source left open.
    mtd finish()
    {
        .parseSource(true)
        while .stack.count > 1 do
            .stack.removeBack()
        .done = true
    }

    private mtd parseSource(final: bool)
    {
        let source = .document.source()
        var index  = .parseIndex

        while index < @countof(source)
        {
            if .inRawText
            {
                let next = .readRawText(source, index)
                if next == Swag.U64.Max
                {
                    if !final do
                        break

                    .emitRawText(source[index to], index)
                    .inRawText = false
                    .stack.removeBack()
                    index = @countof(source)
                    break
                }

                index       = next
                .parseIndex = index
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

                index       = next
                .parseIndex = index
                continue
            }

            // The run ends at the next `<`, and the same pass reports the `&` that would make it
            // need decoding: a run of a page's text is then read once, not twice.
            var end          = index
            var hasReference = false
            while true
            {
                let next = Utf8.indexOfAny(source, @mkslice(&HtmlTextStops[0], 2), end)
                if next == Swag.U64.Max
                {
                    end = @countof(source)
                    break
                }

                if source[next] == '<'
                {
                    end = next
                    break
                }

                hasReference = true
                end          = next + 1
            }

            var text = source[index until end]
            if !final and end == @countof(source)
            {
                let safe = HtmlParser.safeTextEnd(text)
                text = text[0 until safe]
                .emitText(text, hasReference, index)
                index      += safe
                .parseIndex = index
                break
            }

            .emitText(text, hasReference, index)
            index       = end
            .parseIndex = index
        }

        if final do
            .parseIndex = @countof(source)
    }
}
