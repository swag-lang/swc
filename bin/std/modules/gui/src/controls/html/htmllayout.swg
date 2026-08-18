#global internal

using Core, Pixel

// Turns a styled document into a tree of positioned boxes.
//
// Building and laying out are separate passes on purpose: text is measured once when the boxes
// are built, and a resize only breaks the lines again. That is what makes a window resize cost
// line breaking rather than a full re-shaping of every word in the document.
#[Swag.NoDoc]
public struct HtmlLayout
{
    #[Swag.Late]
    {
        document: *HtmlDocument
        pool:     *HtmlValuePool
        theme:    *Theme
    }

    images: #null *HtmlImageCache

    defaults:     HtmlStyleDefaults
    styles:       Array'HtmlComputedStyle
    boxes:        Array'HtmlBox
    pseudoStyles: HashTable'(u64, u32)
    nodeBox:      HashTable'(u32, u32)
    root = HtmlNoNode

    viewport:       Math.Point
    documentHeight: f32
    deviceScale:    f32 = 1
    widthCache:     HashTable'(u64, f32)
}

// The size a box resolves its percentages against.
#[Swag.NoDoc]
public struct HtmlContainingBlock
{
    width:     f32
    height:    f32
    hasHeight: bool
}

// The two widths a box needs before it can be shrink-wrapped or put in a table column.
#[Swag.NoDoc]
public struct HtmlIntrinsicWidths
{
    min: f32
    max: f32
}

impl HtmlLayout
{
    mtd box(index: u32)->*HtmlBox => &.boxes[index]

    mtd const constBox(index: u32)->const *HtmlBox => &.boxes[index]

    mtd style(index: u32)->*HtmlComputedStyle => &.styles[index]

    mtd const constStyle(index: u32)->const *HtmlComputedStyle => &.styles[index]

    // Returns the style that governs a node, which for text is the style of the element that
    // contains it.
    mtd const styleOfNode(node: u32)->const *HtmlComputedStyle
    {
        var walk = node
        while walk != HtmlNoNode and .document.constNode(walk).kind != .Element do
            walk = .document.constNode(walk).parent
        return &.styles[walk == HtmlNoNode ? 0 : walk]
    }

    // Returns the font a style asks for, mapped onto the faces the theme actually carries.
    mtd font(styleIndex: u32)->*Font
    {
        let style = &.styles[styleIndex]
        let size  = cast(u32) Math.clamp(Math.round(style.fontSize), 6, 300)
        let bold  = style.fontWeight >= 600
        var face  = FontFamilyStyle.Regular
        if bold and style.italic do
            face = .BoldItalic
        elif bold do
            face = .Bold
        elif style.italic do
            face = .Italic

        if style.fontFamily == .Mono do
            return .theme.createDefaultFontFS(size, face)
        return .theme.createDefaultFont(size, face)
    }

    // Measures one text run, remembering the answer because a document repeats its words.
    //
    // The measurement is the snapped one: glyphs are drawn on the device pixel grid, and a run
    // measured with its unsnapped advances drifts from what is painted. Over a line of separately
    // placed words the drift eats the spaces between them, so the two must agree.
    //
    // The style index stands for the font: two styles that resolve to the same face simply keep
    // two entries, which costs a little memory and never a wrong width.
    mtd measure(styleIndex: u32, text: string)->f32
    {
        if !@countof(text) do
            return 0

        let key   = Hash.murmur3(Hash.hash64(text), cast(u64) styleIndex)
        let found = .widthCache.tryFind(key)
        if found do
            return found!.value

        // CSS puts the tracking after every character, the shaper only between two of them, so
        // one more gap closes the run. Without it every word of a tracked line is a gap short and
        // the spaces between them disappear.
        let spacing = .styles[styleIndex].letterSpacing
        let width   = Painter.measureStringSnapped(text, .font(styleIndex), Swag.U64.Max, DefaultTextTabSize, spacing, .deviceScale) + spacing
        .widthCache.add(key, width)
        return width
    }

    // Resolves the containing-block context one length needs.
    mtd const lengthContext(styleIndex: u32, basis: f32, hasBasis: bool)->HtmlLengthContext
    {
        var result: retval
        result.fontSize       = .styles[styleIndex].fontSize
        result.rootFontSize   = .defaults.fontSize
        result.viewportWidth  = .viewport.x
        result.viewportHeight = .viewport.y
        result.basis          = basis
        result.hasBasis       = hasBasis
        return result
    }

    mtd const resolveLength(length: HtmlLength, styleIndex: u32, basis: f32, fallback = 0.0'f32)->f32
    {
        return length.resolve(.pool, .lengthContext(styleIndex, basis, true), fallback)
    }
}

// Box tree construction.
impl HtmlLayout
{
    private mtd newBox(node: u32, styleIndex: u32, kind: HtmlBoxKind)->u32
    {
        var box: HtmlBox
        box.node  = node
        box.style = styleIndex
        box.kind  = kind

        let index = cast(u32) .boxes.count
        .boxes.add(#move box)
        if node != HtmlNoNode do
            .nodeBox.add(node, index)
        return index
    }

    // Adds a style that no element owns, for an anonymous or generated box.
    private mtd addStyle(style: HtmlComputedStyle)->u32
    {
        let index = cast(u32) .styles.count
        .styles.add(style)
        return index
    }

    private func kindFor(display: HtmlDisplay)->HtmlBoxKind
    {
        switch display
        {
        case .Flex, .InlineFlex: return .Flex
        case .Grid, .InlineGrid: return .Grid
        case .Table:             return .Table
        case .TableRow:          return .TableRow
        case .TableCell:         return .TableCell
        }

        return .Block
    }

    // Builds the whole box tree from a styled document.
    mtd build(document: *HtmlDocument, resolver: *HtmlStyleResolver, theme: *Theme, images: #null *HtmlImageCache)
    {
        .document = document
        .theme    = theme
        .images   = images
        .defaults = resolver.defaults
        .pool     = resolver.pool
        .styles   = #move resolver.styles
        .boxes.clear()
        .widthCache.clear()
        .pseudoStyles.clear()
        .nodeBox.clear()

        // Generated styles join the element ones so a box only ever indexes a single table.
        for value in resolver.pseudos
        {
            .pseudoStyles.add(HtmlStyleResolver.pseudoKey(value.element, value.which), cast(u32) .styles.count)
            .styles.add(value.style)
        }

        var rootStyle = HtmlComputedStyle.fromDefaults(.defaults)
        rootStyle.display = .Block
        .root             = .newBox(HtmlNoNode, .addStyle(rootStyle), .Block)

        var pending: Array'HtmlInlineItem
        for child in document.constNode(0).children do
            .buildChild(.root, child, &pending)
        .flushInline(.root, &pending, true)
    }

    // Emits one DOM child into the box that contains it.
    private mtd buildChild(parentBox: u32, node: u32, pending: *Array'HtmlInlineItem)
    {
        let child = .document.constNode(node)
        if child.kind == .Text
        {
            .appendText(pending, node, .styleIndexOf(node), child.text.toString())
            return
        }

        if child.kind != .Element do
            return

        let style = &.styles[node]
        if style.display == .None do
            return

        if style.display == .Contents
        {
            .buildInlineChildren(parentBox, node, pending)
            return
        }

        if child.tag == .Br
        {
            var item: HtmlInlineItem
            item.kind  = .Break
            item.style = node
            item.node  = node
            pending.add(#move item)
            return
        }

        if style.isOutOfFlow()
        {
            // A positioned box leaves the flow entirely; it is still a child of this box so the
            // painter finds it, and it is laid out against the box it is positioned in.
            .flushInline(parentBox, pending, false)
            let box = .buildBox(parentBox, node)
            .boxes[parentBox].children.add(box)
            return
        }

        // Every element child of a flex or grid container is one of its items, whatever display it
        // asked for. Only a run of raw text becomes an anonymous item.
        let container = .boxes[parentBox].kind
        if container == .Flex or container == .Grid
        {
            .flushInline(parentBox, pending, false)
            let item = .buildBox(parentBox, node)
            .boxes[parentBox].children.add(item)
            return
        }

        if style.isInlineLevel()
        {
            if style.display == .Inline
            {
                .buildInlineBox(parentBox, node, pending)
                return
            }

            // An atomic inline is a real box that occupies one item of the line.
            let box = .buildBox(parentBox, node)
            var item: HtmlInlineItem
            item.kind  = .Atomic
            item.style = node
            item.node  = node
            item.box   = box
            pending.add(#move item)
            return
        }

        .flushInline(parentBox, pending, false)
        let box = .buildBox(parentBox, node)
        .boxes[parentBox].children.add(box)
    }

    // Emits an inline element as a run of items framed by its open and close markers.
    private mtd buildInlineBox(parentBox: u32, node: u32, pending: *Array'HtmlInlineItem)
    {
        // The two edge widths are read before anything else runs, because building the content of
        // this element can append generated styles and move the table they were read from.
        let basis     = .viewport.x
        let leftEdge  = .resolveLength(.styles[node].padding.left, node, basis) + .styles[node].borderLeft.width
        let rightEdge = .resolveLength(.styles[node].padding.right, node, basis) + .styles[node].borderRight.width

        var open: HtmlInlineItem
        open.kind  = .OpenInline
        open.style = node
        open.node  = node
        open.width = leftEdge
        pending.add(#move open)

        .emitPseudo(parentBox, node, .Before, pending)
        .buildInlineChildren(parentBox, node, pending)
        .emitPseudo(parentBox, node, .After, pending)

        var close: HtmlInlineItem
        close.kind  = .CloseInline
        close.style = node
        close.node  = node
        close.width = rightEdge
        pending.add(#move close)
    }

    private mtd buildInlineChildren(parentBox: u32, node: u32, pending: *Array'HtmlInlineItem)
    {
        let children = .document.constNode(node).children
        for child in children do
            .buildChild(parentBox, child, pending)
    }

    // Emits the text a `::before` or `::after` rule generates.
    private mtd emitPseudo(parentBox: u32, node: u32, which: HtmlPseudoElement, pending: *Array'HtmlInlineItem)
    {
        let style = .pseudoStyleIndex(node, which)
        if style == HtmlNoNode do
            return

        if .styles[style].isOutOfFlow()
        {
            let item = .newBox(HtmlNoNode, style, HtmlLayout.kindFor(.styles[style].display))
            .boxes[item].parent = parentBox
            .boxes[parentBox].children.add(item)
            return
        }

        // A generated box inside a flex or grid container is one of its items, and is therefore
        // block-level whatever it asked for. That is what makes a decorative rule with a width
        // and a height draw its bar instead of collapsing into an empty inline box.
        let container = .boxes[parentBox].kind
        let blockify  = container == .Flex or container == .Grid
        let display   = .styles[style].display
        if display != .Inline or blockify
        {
            if blockify
            {
                .flushInline(parentBox, pending, false)
                let item = .newBox(HtmlNoNode, style, display == .Inline ? HtmlBoxKind.Block : HtmlLayout.kindFor(display))
                .boxes[item].parent = parentBox
                .boxes[parentBox].children.add(item)
                return
            }

            let box = .newBox(HtmlNoNode, style, HtmlLayout.kindFor(display))
            .boxes[box].parent = parentBox

            var item: HtmlInlineItem
            item.kind  = .Atomic
            item.style = style
            item.node  = node
            item.box   = box
            pending.add(#move item)
            return
        }

        if .styles[style].hasContent do
            .appendText(pending, node, style, .pool.text(.styles[style].content))
    }

    // Records the style a pseudo-element selector produced, copying it into the layout's own
    // table so a box only ever refers to one array.
    private mtd pseudoStyleIndex(node: u32, which: HtmlPseudoElement)->u32
    {
        let key   = HtmlStyleResolver.pseudoKey(node, which)
        let found = .pseudoStyles.tryFind(key)
        return found ? found!.value : HtmlNoNode
    }

    // Builds one box and everything it contains.
    private mtd buildBox(parentBox: u32, node: u32)->u32
    {
        let display = .styles[node].display
        let box     = .newBox(node, node, HtmlLayout.kindFor(display))
        .boxes[box].parent = parentBox

        if .document.constNode(node).tag == .Img or .document.constNode(node).tag == .Embed
        {
            .boxes[box].kind = .Replaced
            return box
        }

        var pending: Array'HtmlInlineItem
        .emitPseudo(box, node, .Before, &pending)

        let children = .document.constNode(node).children
        for child in children do
            .buildChild(box, child, &pending)

        .emitPseudo(box, node, .After, &pending)
        .flushInline(box, &pending, true)

        if display == .ListItem do
            .buildMarker(box, node)
        if .document.constNode(node).tag == .Summary do
            .buildDisclosureMarker(box, node)

        // A ticked box is drawn inside its own border rather than beside it, so it takes no
        // marker width.
        if .document.constNode(node).tag == .Input and .document.hasAttribute(node, "checked") do
            .boxes[box].markerKind = .Checked
        if .boxes[box].kind == .Table do
            .flattenTable(box)
        return box
    }

    // Moves the accumulated inline items into the box, wrapping them in an anonymous block when
    // the box already holds block children and the two would otherwise fight over the same flow.
    private mtd flushInline(box: u32, pending: *Array'HtmlInlineItem, final: bool)
    {
        if pending.isEmpty() do
            return

        if !HtmlLayout.hasVisibleItem(pending)
        {
            pending.clear()
            return
        }

        // A flex, grid or table container has no inline formatting context of its own: every run
        // of inline content becomes an anonymous item, which is what makes text written directly
        // inside a flex row take part in that row.
        let ownsInline = .boxes[box].kind == .Block
        if final and ownsInline and .boxes[box].children.isEmpty()
        {
            .boxes[box].items = #move pending[]
            pending.clear()
            return
        }

        var anonymous = HtmlComputedStyle.inherited(.styles[.boxes[box].style])
        anonymous.display = .Block

        let wrapper = .newBox(HtmlNoNode, .addStyle(anonymous), .Block)
        .boxes[wrapper].parent = box
        .boxes[wrapper].items  = #move pending[]
        pending.clear()
        .boxes[box].children.add(wrapper)
    }

    // Reports whether a run of items would draw anything, so a document's indentation whitespace
    // never becomes an empty anonymous line.
    private func hasVisibleItem(pending: const *Array'HtmlInlineItem)->bool
    {
        for item in pending
        {
            switch item.kind
            {
            case .Text, .Atomic, .Break: return true
            }
        }

        return false
    }

    // Gives a list item the marker its list asks for.
    private mtd buildMarker(box: u32, node: u32)
    {
        let style = &.styles[node]
        if style.listStyleType == .None do
            return

        var ordinal = 1'u32
        let parent  = .document.constNode(node).parent
        if parent != HtmlNoNode
        {
            var seen = 0'u32
            for sibling in .document.constNode(parent).children
            {
                if .document.constNode(sibling).kind != .Element do
                    continue
                if .styles[sibling].display != .ListItem do
                    continue
                seen += 1
                if sibling == node do
                    ordinal = seen
            }
        }

        .boxes[box].marker      = HtmlLayout.markerText(style.listStyleType, ordinal)
        .boxes[box].markerKind  = .Text
        .boxes[box].markerWidth = .measure(.boxes[box].style, .boxes[box].marker.toString())
    }

    // Gives a disclosure summary the triangle that says whether its details are open.
    private mtd buildDisclosureMarker(box: u32, node: u32)
    {
        let parent = .document.constNode(node).parent
        if parent == HtmlNoNode or .document.constNode(parent).tag != .Details do
            return

        // `list-style: none` is how a document says it draws the disclosure arrow itself.
        if .styles[.boxes[box].style].listStyleType == .None do
            return

        // The triangle is drawn rather than set in text: a theme typeface carries no guarantee
        // about the geometric shapes, and a missing glyph would put a box where the arrow goes.
        .boxes[box].markerKind  = .document.hasAttribute(parent, "open") ? HtmlMarkerKind.DisclosureOpen : HtmlMarkerKind.DisclosureClosed
        .boxes[box].markerWidth = Math.round(.styles[.boxes[box].style].fontSize * 0.75)
    }

    // Renders one list marker.
    func markerText(kind: HtmlListStyleType, ordinal: u32)->String
    {
        switch kind
        {
        case .Disc:
            return "•"

        case .Circle:
            return "◦"

        case .Square:
            return "▪"

        case .Decimal:
            return Format.toString("%.", ordinal)

        case .LowerAlpha, .UpperAlpha:
            var result: String
            var value = ordinal
            while value
            {
                let digit = cast(u8) ((value - 1) % 26)
                result = Format.toString("%%", cast(rune) ((kind == .LowerAlpha ? 'a'u8 : 'A'u8) + digit), result)
                value  = (value - 1) / 26
            }

            result += "."
            return result

        case .LowerRoman, .UpperRoman:
            var result = HtmlLayout.romanNumeral(ordinal)
            if kind == .LowerRoman do
                result = result.toLower()
            result += "."
            return result
        }

        return ""
    }

    private func romanNumeral(value: u32)->String
    {
        const Values = [1000'u32, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        const Signs  = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]

        var result: retval
        var left = value
        for index in @countof(Values)
        {
            while left >= Values[index]
            {
                result += Signs[index]
                left   -= Values[index]
            }
        }

        return result
    }

    // Replaces the row groups of a table by the rows they hold, so the layout only ever sees
    // rows and cells.
    private mtd flattenTable(box: u32)
    {
        var rows: Array'u32
        let children = .boxes[box].children
        for child in children
        {
            if .styles[.boxes[child].style].display == .TableRowGroup
            {
                let inner = .boxes[child].children
                for row in inner
                {
                    .boxes[row].parent = box
                    rows.add(row)
                }

                continue
            }

            rows.add(child)
        }

        .boxes[box].children = #move rows
    }

    private mtd styleIndexOf(node: u32)->u32
    {
        var walk = node
        while walk != HtmlNoNode and .document.constNode(walk).kind != .Element do
            walk = .document.constNode(walk).parent
        return walk == HtmlNoNode ? 0 : walk
    }
}

// Inline item generation.
private impl HtmlLayout
{
    // Applies `text-transform` to one word.
    func transform(text: string, kind: HtmlTextTransform)->String
    {
        switch kind
        {
        case .Uppercase:
            return String.from(text).toUpper()

        case .Lowercase:
            return String.from(text).toLower()

        case .Capitalize:
            var result = String.from(text)
            if result.length do
                result[0] = Latin1.toUpper(result[0])
            return result
        }

        return String.from(text)
    }

    // Native byte reads can be widened to one machine word. Keep the final bytes in padded
    // local storage so a text slice ending on a guard-page boundary remains safe to scan.
    #[Swag.Optimize(false)]
    func wordEnd(text: string, start: u64)->u64
    {
        let length    = @countof(text)
        let directEnd = length > 7 ? length - 7 : 0
        var result    = start
        while result < directEnd
        {
            if Latin1.isSpace(text[result]) do
                return result
            result += 1
        }

        if result >= length do
            return result

        var tail: [16] u8
        let tailCount = length - result
        @memcpy(&tail[0], @dataof(text) + result, tailCount)
        for index in tailCount
        {
            if Latin1.isSpace(tail[index]) do
                return result + index
        }

        return length
    }

    // Splits a text node into the items an inline formatting context lays out.
    //
    // White space is where the two rendering modes differ: normal text collapses every run of
    // spaces into one break opportunity, while preformatted text keeps what the source wrote and
    // turns each newline into a forced break.
    mtd appendText(pending: *Array'HtmlInlineItem, node: u32, styleIndex: u32, text: string)
    {
        let style      = &.styles[styleIndex]
        let font       = .font(styleIndex)
        let collapse   = style.whiteSpace == .Normal or style.whiteSpace == .NoWrap
        let keepBreaks = style.whiteSpace == .Pre or style.whiteSpace == .PreWrap or style.whiteSpace == .PreLine
        let keepSpaces = style.whiteSpace == .Pre or style.whiteSpace == .PreWrap

        var index = 0'u64
        while index < @countof(text)
        {
            let character = text[index]
            if character == '\n' or character == '\r'
            {
                var eat = 1'u64
                if character == '\r' and index + 1 < @countof(text) and text[index + 1] == '\n' do
                    eat = 2
                if keepBreaks
                {
                    var item: HtmlInlineItem
                    item.kind        = .Break
                    item.style       = styleIndex
                    item.node        = node
                    item.sourceStart = index
                    item.sourceEnd   = index + eat
                    pending.add(#move item)
                }
                else do
                    .appendSpace(pending, node, styleIndex, font, collapse, index, index + eat)
                index += eat
                continue
            }

            if Latin1.isSpace(character)
            {
                if !keepSpaces
                {
                    .appendSpace(pending, node, styleIndex, font, collapse, index, index + 1)
                    index += 1
                    continue
                }

                var end = index
                while end < @countof(text) and (text[end] == ' ' or text[end] == '\t') do
                    end += 1

                var item: HtmlInlineItem
                item.kind        = .Space
                item.style       = styleIndex
                item.node        = node
                item.text        = text[index until end]
                item.sourceStart = index
                item.sourceEnd   = end
                item.width       = .measure(styleIndex, item.text.toString())
                item.ascent      = font.ascent
                item.descent     = -font.descent
                pending.add(#move item)
                index = end
                continue
            }

            let end = HtmlLayout.wordEnd(text, index)

            var item: HtmlInlineItem
            item.kind        = .Text
            item.style       = styleIndex
            item.node        = node
            item.text        = HtmlLayout.transform(text[index until end], style.textTransform)
            item.sourceStart = index
            item.sourceEnd   = end
            item.width       = .measure(styleIndex, item.text.toString())
            item.ascent      = font.ascent
            item.descent     = -font.descent
            pending.add(#move item)
            index = end
        }
    }

    // Adds one collapsible space, unless the previous item already opened one.
    mtd appendSpace(pending: *Array'HtmlInlineItem, node: u32, styleIndex: u32, font: *Font, collapse: bool, sourceStart, sourceEnd: u64)
    {
        if collapse and pending.count
        {
            let previous = pending.backPtr()
            if previous.kind == .Space or previous.kind == .Break
            {
                if previous.node == node do
                    previous.sourceEnd = sourceEnd
                return
            }
        }

        if collapse and pending.isEmpty() do
            return

        var item: HtmlInlineItem
        item.kind        = .Space
        item.style       = styleIndex
        item.node        = node
        item.text        = " "
        item.sourceStart = sourceStart
        item.sourceEnd   = sourceEnd
        item.width       = .measure(styleIndex, " ")
        item.ascent      = font.ascent
        item.descent     = -font.descent
        pending.add(#move item)
    }
}

// Box geometry.
impl HtmlLayout
{
    // Returns the space a box adds around its content on the horizontal axis.
    private mtd const horizontalExtra(box: u32, containingWidth: f32)->f32
    {
        let style  = &.styles[.boxes[box].style]
        var result = style.borderWidthX()
        result += .resolveLength(style.padding.left, .boxes[box].style, containingWidth)
        result += .resolveLength(style.padding.right, .boxes[box].style, containingWidth)
        return result
    }

    private mtd const verticalExtra(box: u32, containingWidth: f32)->f32
    {
        let style  = &.styles[.boxes[box].style]
        var result = style.borderWidthY()
        result += .resolveLength(style.padding.top, .boxes[box].style, containingWidth)
        result += .resolveLength(style.padding.bottom, .boxes[box].style, containingWidth)
        return result
    }

    // Reports whether a box keeps its children's margins inside itself, which is what stops a
    // margin from collapsing through its edge.
    private mtd const sealsTopMargin(box: u32, containingWidth: f32)->bool
    {
        let style = &.styles[.boxes[box].style]
        if style.borderTop.width > 0 do
            return true
        if .resolveLength(style.padding.top, .boxes[box].style, containingWidth) > 0 do
            return true
        if .boxes[box].kind != .Block do
            return true
        if style.overflowY != .Visible or style.position == .Absolute or style.position == .Fixed do
            return true
        return .boxes[box].items.count != 0
    }

    private mtd const sealsBottomMargin(box: u32, containingWidth: f32)->bool
    {
        let style = &.styles[.boxes[box].style]
        if style.borderBottom.width > 0 do
            return true
        if .resolveLength(style.padding.bottom, .boxes[box].style, containingWidth) > 0 do
            return true
        if .boxes[box].kind != .Block do
            return true
        if style.overflowY != .Visible or style.position == .Absolute or style.position == .Fixed do
            return true
        if !style.height.isAuto() do
            return true
        return .boxes[box].items.count != 0
    }

    // Returns the top margin a box exposes, after the margins of its first children have
    // collapsed into it.
    private mtd const collapsedTop(box: u32, containingWidth: f32)->f32
    {
        let style  = &.styles[.boxes[box].style]
        var result = .resolveLength(style.margin.top, .boxes[box].style, containingWidth)
        if .sealsTopMargin(box, containingWidth) do
            return result

        let inner = Math.max(containingWidth - .horizontalExtra(box, containingWidth), 0)
        for child in .boxes[box].children
        {
            if .styles[.boxes[child].style].isOutOfFlow() do
                continue
            result = Math.max(result, .collapsedTop(child, inner))
            break
        }

        return result
    }

    private mtd const collapsedBottom(box: u32, containingWidth: f32)->f32
    {
        let style  = &.styles[.boxes[box].style]
        var result = .resolveLength(style.margin.bottom, .boxes[box].style, containingWidth)
        if .sealsBottomMargin(box, containingWidth) do
            return result

        let inner = Math.max(containingWidth - .horizontalExtra(box, containingWidth), 0)
        var last  = HtmlNoNode
        for child in .boxes[box].children where !.styles[.boxes[child].style].isOutOfFlow() do
            last = child
        if last != HtmlNoNode do
            result = Math.max(result, .collapsedBottom(last, inner))
        return result
    }

    // Measures what a box would take on one line, and what it needs at its narrowest.
    mtd intrinsicWidths(box: u32)->HtmlIntrinsicWidths
    {
        if .boxes[box].hasIntrinsic do
            return {.boxes[box].minContent, .boxes[box].maxContent}

        var result: retval
        let style = &.styles[.boxes[box].style]

        if .boxes[box].kind == .Replaced
        {
            let size = .replacedSize(box, .viewport.x)
            result.min = size.x
            result.max = size.x
        }
        elif .boxes[box].items.count
        {
            var line = 0.0'f32
            for item in .boxes[box].items
            {
                var width = item.width
                if item.kind == .Atomic and item.box != HtmlNoNode
                {
                    let inner = .intrinsicWidths(item.box)
                    width      = inner.max
                    result.min = Math.max(result.min, inner.min)
                }
                elif item.kind == .Text do
                    result.min = Math.max(result.min, width)

                if item.kind == .Break
                {
                    line = 0
                    continue
                }

                line       += width
                result.max = Math.max(result.max, line)
            }
        }
        elif .boxes[box].kind == .Flex and .styles[.boxes[box].style].flexDirection == .Row
        {
            var minimum = 0.0'f32
            var count   = 0'u32
            for child in .boxes[box].children
            {
                let inner = .intrinsicWidths(child)
                result.min = Math.max(result.min, inner.min)
                result.max += inner.max
                minimum    += inner.min
                count      += 1
            }

            if count > 1
            {
                let gap = .resolveLength(style.columnGap, .boxes[box].style, .viewport.x) * cast(f32) (count - 1)
                result.max += gap
                if style.flexWrap == .NoWrap do
                    result.min = minimum + gap
            }
        }
        else
        {
            for child in .boxes[box].children where !.styles[.boxes[child].style].isOutOfFlow()
            {
                let inner = .intrinsicWidths(child)
                result.min = Math.max(result.min, inner.min)
                result.max = Math.max(result.max, inner.max)
            }
        }

        // A definite width overrides what the content would ask for.
        if style.width.kind == .Pixels
        {
            result.min = style.width.value
            result.max = style.width.value
        }

        let extra = .horizontalExtra(box, .viewport.x)
        result.min += extra + .boxes[box].markerWidth
        result.max += extra + .boxes[box].markerWidth

        .boxes[box].minContent   = result.min
        .boxes[box].maxContent   = result.max
        .boxes[box].hasIntrinsic = true
        return result
    }

    // Returns the size a replaced element draws at.
    private mtd replacedSize(box: u32, containingWidth: f32)->Math.Point
    {
        var result: retval
        let node  = .boxes[box].node
        let style = &.styles[.boxes[box].style]

        var natural = Math.Point{0, 0}
        if .images and node != HtmlNoNode
        {
            let entry = .images!.fetch(.document.attribute(node, "src"))
            if entry
            {
                natural.x = cast(f32) entry!.image.width
                natural.y = cast(f32) entry!.image.height
            }
        }

        if node != HtmlNoNode and !natural.x
        {
            let width  = htmlParseNumber(.document.attribute(node, "width"))
            let height = htmlParseNumber(.document.attribute(node, "height"))
            if width.eat do
                natural.x = width.value
            if height.eat do
                natural.y = height.value
        }

        // An image the engine could not read still occupies the room a document reserved for it,
        // so the text around it keeps the shape the author intended.
        if !natural.x do
            natural.x = 20
        if !natural.y do
            natural.y = 20

        result = natural
        if !style.width.isAuto() and !style.width.isNone() do
            result.x = .resolveLength(style.width, .boxes[box].style, containingWidth, natural.x)
        if !style.maxWidth.isAuto() and !style.maxWidth.isNone() do
            result.x = Math.min(result.x, .resolveLength(style.maxWidth, .boxes[box].style, containingWidth, result.x))
        if !style.height.isAuto() and !style.height.isNone() do
            result.y = .resolveLength(style.height, .boxes[box].style, containingWidth, natural.y)
        elif natural.x > 0 do
            result.y = natural.y * result.x / natural.x

        return result
    }

    // Moves a box and everything it contains, which is what relative positioning does once the
    // normal flow has already placed the subtree.
    private mtd translate(box: u32, dx, dy: f32)
    {
        if !dx and !dy do
            return

        .boxes[box].rect.offset(dx, dy)
        .boxes[box].content.offset(dx, dy)
        for &item in .boxes[box].items
        {
            item.x += dx
            item.y += dy
        }

        let children = .boxes[box].children
        for child in children do
            .translate(child, dx, dy)
        for index in .boxes[box].items.count where .boxes[box].items[index].box != HtmlNoNode do
            .translate(.boxes[box].items[index].box, dx, dy)
    }

    // Moves what a box contains while leaving its own border and content rectangles in place.
    // Table-cell alignment uses this after the row has established a taller shared cell height.
    private mtd translateContents(box: u32, dx, dy: f32)
    {
        if !dx and !dy do
            return

        for &item in .boxes[box].items
        {
            item.x += dx
            item.y += dy
        }

        let children = .boxes[box].children
        for child in children do
            .translate(child, dx, dy)
        for index in .boxes[box].items.count where .boxes[box].items[index].box != HtmlNoNode do
            .translate(.boxes[box].items[index].box, dx, dy)
    }
}

// Flow layout.
impl HtmlLayout
{
    // Lays the whole document out inside a viewport.
    mtd layout(width, height: f32)
    {
        if .root == HtmlNoNode do
            return

        .viewport = {Math.max(width, 1), Math.max(height, 1)}
        for &box in .boxes do
            box.hasIntrinsic = false

        var containing: HtmlContainingBlock
        containing.width     = .viewport.x
        containing.height    = .viewport.y
        containing.hasHeight = true

        .boxes[.root].rect    = {0, 0, .viewport.x, 0}
        .boxes[.root].content = {0, 0, .viewport.x, 0}

        let contentHeight = .layoutBlockChildren(.root, 0, 0, .viewport.x, containing)
        .boxes[.root].rect.height    = contentHeight
        .boxes[.root].content.height = contentHeight
        let paintBounds = .computePaintBounds(.root)
        .documentHeight = Math.max(contentHeight, paintBounds.bottom())
    }

    // Records the complete visible extent of every subtree. A parent with visible overflow can
    // leave the viewport before a tall image or positioned descendant that escapes it does.
    private mtd computePaintBounds(box: u32)->Math.Rectangle
    {
        var result  = .boxes[box].rect
        let style   = &.styles[.boxes[box].style]
        let expands = style.overflowX == .Visible and style.overflowY == .Visible

        let children = .boxes[box].children
        for child in children
        {
            let childBounds = .computePaintBounds(child)
            if expands do
                result.combine(childBounds)
        }

        for item in .boxes[box].items where item.box != HtmlNoNode
        {
            let childBounds = .computePaintBounds(item.box)
            if expands do
                result.combine(childBounds)
        }

        .boxes[box].paintBounds = result
        return result
    }

    // Stacks the in-flow children of a block container, collapsing the margins between them.
    private mtd layoutBlockChildren(box: u32, contentX, contentY, contentWidth: f32, containing: HtmlContainingBlock)->f32
    {
        var inner: HtmlContainingBlock
        inner.width = contentWidth

        var y            = contentY
        var previousEdge = 0.0'f32
        var first        = true
        let sealsTop     = .sealsTopMargin(box, containing.width)
        let sealsBottom  = .sealsBottomMargin(box, containing.width)

        let children = .boxes[box].children
        for child in children
        {
            if .styles[.boxes[child].style].isOutOfFlow()
            {
                .layoutAbsolute(child, box, containing)
                continue
            }

            let childTop = .collapsedTop(child, contentWidth)
            let gap      = first ? (sealsTop ? childTop : 0) : Math.max(previousEdge, childTop)

            .layoutBlockBox(child, contentX, y + gap, contentWidth, inner)
            y            = .boxes[child].rect.bottom()
            previousEdge = .collapsedBottom(child, contentWidth)
            first        = false
        }

        // The last child's bottom margin only counts inside this box when the box keeps it; a box
        // that lets it through already reported it as its own collapsed bottom margin.
        var height = y - contentY
        if sealsBottom and !first do
            height += previousEdge
        return Math.max(height, 0)
    }

    // Places one block-level box, given the position its collapsed top margin already produced.
    mtd layoutBlockBox(box: u32, originX, originY, containingWidth: f32, containing: HtmlContainingBlock)
    {
        let styleIndex = .boxes[box].style
        let style      = &.styles[styleIndex]

        let borderX   = style.borderWidthX()
        let borderY   = style.borderWidthY()
        let padLeft   = .resolveLength(style.padding.left, styleIndex, containingWidth)
        let padRight  = .resolveLength(style.padding.right, styleIndex, containingWidth)
        let padTop    = .resolveLength(style.padding.top, styleIndex, containingWidth)
        let padBottom = .resolveLength(style.padding.bottom, styleIndex, containingWidth)
        let extraX    = borderX + padLeft + padRight
        let extraY    = borderY + padTop + padBottom

        var marginLeft  = style.margin.left.isAuto() ? 0 : .resolveLength(style.margin.left, styleIndex, containingWidth)
        var marginRight = style.margin.right.isAuto() ? 0 : .resolveLength(style.margin.right, styleIndex, containingWidth)

        var borderWidth: f32
        if style.width.isAuto() or style.width.isNone() or style.width.isIntrinsic()
        {
            borderWidth = Math.max(containingWidth - marginLeft - marginRight, 0)
            if style.width.isIntrinsic()
            {
                let intrinsic = .intrinsicWidths(box)
                let wanted    = style.width.kind == .MinContent ? intrinsic.min : intrinsic.max
                borderWidth = Math.min(borderWidth, wanted)
            }
        }
        else
        {
            let value = .resolveLength(style.width, styleIndex, containingWidth)
            borderWidth = style.boxSizing == .BorderBox ? value : value + extraX
        }

        borderWidth = .clampWidth(borderWidth, style, styleIndex, containingWidth, extraX)

        // Two automatic side margins center the box in what contains it.
        if style.margin.left.isAuto() and style.margin.right.isAuto() and borderWidth < containingWidth
        {
            marginLeft  = (containingWidth - borderWidth) * 0.5
            marginRight = marginLeft
        }
        elif style.margin.left.isAuto() and borderWidth < containingWidth do
            marginLeft = containingWidth - borderWidth - marginRight

        let x            = originX + marginLeft
        let contentWidth = Math.max(borderWidth - extraX, 0)
        let contentX     = x + style.borderLeft.width + padLeft
        let contentY     = originY + style.borderTop.width + padTop

        .boxes[box].rect    = {x, originY, borderWidth, extraY}
        .boxes[box].content = {contentX, contentY, contentWidth, 0}

        var inner: HtmlContainingBlock
        inner.width = contentWidth

        var contentHeight: f32
        switch .boxes[box].kind
        {
        case .Replaced:
            let size = .replacedSize(box, containingWidth)
            contentHeight = size.y
            if style.width.isAuto() or style.width.isNone()
            {
                borderWidth               = size.x + extraX
                .boxes[box].rect.width    = borderWidth
                .boxes[box].content.width = size.x
            }

        case .Flex:
            contentHeight = .layoutFlex(box, contentX, contentY, contentWidth, inner)

        case .Grid:
            contentHeight = .layoutGrid(box, contentX, contentY, contentWidth, inner)

        case .Table:
            contentHeight = .layoutTable(box, contentX, contentY, contentWidth, inner)

        case .TableRow, .TableCell:
            contentHeight = .layoutBlockChildren(box, contentX, contentY, contentWidth, inner)

        default:
            if .boxes[box].items.count do
                contentHeight = .layoutInline(box, contentX, contentY, contentWidth)
            else do
                contentHeight = .layoutBlockChildren(box, contentX, contentY, contentWidth, inner)
        }

        var usedHeight = contentHeight
        if !style.height.isAuto() and !style.height.isNone() and style.height.isDefinite(.pool, containing.hasHeight)
        {
            let value = style.height.resolve(.pool, .lengthContext(styleIndex, containing.height, containing.hasHeight), contentHeight)
            usedHeight = style.boxSizing == .BorderBox ? Math.max(value - extraY, 0) : value
        }

        usedHeight = .clampHeight(usedHeight, style, styleIndex, containing, extraY)

        // A single flex line consumes a definite or minimum cross size. Aligning it only inside
        // its natural text height pins a min-height navigation bar to the top of its own band.
        if .boxes[box].kind == .Flex and usedHeight > contentHeight do
            .expandSingleFlexLine(box, usedHeight - contentHeight, contentWidth)

        // A region that limits its height and admits overflow scrolls on its own.
        .boxes[box].scrollable   = false
        .boxes[box].scrollHeight = contentHeight
        if contentHeight > usedHeight + 0.5 and (style.overflowY == .Auto or style.overflowY == .Scroll) do
            .boxes[box].scrollable = true

        .boxes[box].rect.height    = usedHeight + extraY
        .boxes[box].content.height = usedHeight

        if style.position == .Sticky
        {
            .boxes[box].sticky    = true
            .boxes[box].stickyTop = .resolveLength(style.inset.top, styleIndex, containing.height)
        }

        if style.position == .Relative
        {
            let dx = style.inset.left.isAuto() ? -.resolveLength(style.inset.right, styleIndex, containingWidth) : .resolveLength(style.inset.left, styleIndex, containingWidth)
            let dy = style.inset.top.isAuto() ? -.resolveLength(style.inset.bottom, styleIndex, containing.height) : .resolveLength(style.inset.top, styleIndex, containing.height)
            .translate(box, dx, dy)
        }
    }

    private mtd const clampWidth(width: f32, style: const *HtmlComputedStyle, styleIndex: u32, containingWidth, extraX: f32)->f32
    {
        var result = width
        if !style.maxWidth.isAuto() and !style.maxWidth.isNone()
        {
            let value = .resolveLength(style.maxWidth, styleIndex, containingWidth, result)
            result = Math.min(result, style.boxSizing == .BorderBox ? value : value + extraX)
        }

        if !style.minWidth.isAuto() and !style.minWidth.isNone()
        {
            let value = .resolveLength(style.minWidth, styleIndex, containingWidth, 0)
            result = Math.max(result, style.boxSizing == .BorderBox ? value : value + extraX)
        }

        return Math.max(result, 0)
    }

    private mtd const clampHeight(height: f32, style: const *HtmlComputedStyle, styleIndex: u32, containing: HtmlContainingBlock, extraY: f32)->f32
    {
        var result = height
        if !style.maxHeight.isAuto() and !style.maxHeight.isNone() and style.maxHeight.isDefinite(.pool, containing.hasHeight)
        {
            let value = style.maxHeight.resolve(.pool, .lengthContext(styleIndex, containing.height, containing.hasHeight), result)
            result = Math.min(result, style.boxSizing == .BorderBox ? Math.max(value - extraY, 0) : value)
        }

        if !style.minHeight.isAuto() and !style.minHeight.isNone() and style.minHeight.isDefinite(.pool, containing.hasHeight)
        {
            let value = style.minHeight.resolve(.pool, .lengthContext(styleIndex, containing.height, containing.hasHeight), 0)
            result = Math.max(result, style.boxSizing == .BorderBox ? Math.max(value - extraY, 0) : value)
        }

        return Math.max(result, 0)
    }

    // Places a box that left the normal flow, against the box it is positioned in.
    private mtd layoutAbsolute(box: u32, container: u32, containing: HtmlContainingBlock)
    {
        let styleIndex = .boxes[box].style
        let style      = &.styles[styleIndex]
        let frame      = .boxes[container].content

        var inner: HtmlContainingBlock
        inner.width     = frame.width
        inner.height    = frame.height
        inner.hasHeight = true

        var x = frame.x
        var y = frame.y
        if !style.inset.left.isAuto() do
            x = frame.x + .resolveLength(style.inset.left, styleIndex, frame.width)
        if !style.inset.top.isAuto() do
            y = frame.y + .resolveLength(style.inset.top, styleIndex, frame.height)

        var available = frame.width
        if style.width.isAuto() or style.width.isNone()
        {
            let intrinsic = .intrinsicWidths(box)
            available = Math.clamp(intrinsic.max, 0, frame.width)
        }

        .layoutBlockBox(box, x, y, available, inner)

        if style.inset.left.isAuto() and !style.inset.right.isAuto()
        {
            let right = .resolveLength(style.inset.right, styleIndex, frame.width)
            .translate(box, frame.right() - right - .boxes[box].rect.right(), 0)
        }

        if style.inset.top.isAuto() and !style.inset.bottom.isAuto()
        {
            let bottom = .resolveLength(style.inset.bottom, styleIndex, frame.height)
            .translate(box, 0, frame.bottom() - bottom - .boxes[box].rect.bottom())
        }
    }
}

// Inline formatting.
private impl HtmlLayout
{
    // Returns how far above and below its baseline one item reaches, leading included.
    mtd const itemExtent(box: u32, index: u64)->{ ascent: f32, descent: f32 }
    {
        var result: retval
        let item = &.boxes[box].items[index]
        if item.kind == .Atomic and item.box != HtmlNoNode
        {
            // An atomic inline sits on the baseline by its bottom margin edge.
            result.ascent = .boxes[item.box].rect.height
            return result
        }

        let style   = &.styles[item.style]
        let natural = item.ascent + item.descent
        let line    = style.resolvedLineHeight(.pool, natural)
        let leading = (line - natural) * 0.5
        result.ascent  = item.ascent + leading
        result.descent = item.descent + leading
        return result
    }

    // Places one finished line and returns the height it took.
    mtd finishLine(box: u32, first, last: u64, top, left, available: f32)->f32
    {
        let styleIndex  = .boxes[box].style
        let blockStyle  = &.styles[styleIndex]
        let strut       = .font(styleIndex)
        let strutHeight = blockStyle.resolvedLineHeight(.pool, strut.height)

        if first >= last
        {
            var empty: HtmlLineBox
            empty.top    = top
            empty.height = strutHeight
            empty.left   = left
            empty.first  = cast(u32) first
            empty.last   = cast(u32) last
            .boxes[box].lines.add(#move empty)
            return strutHeight
        }

        // A space that ends a line is not drawn and does not count for alignment.
        var end = last
        while end > first and .boxes[box].items[end - 1].kind == .Space
        {
            .boxes[box].items[end - 1].visible = false
            end -= 1
        }

        var ascent  = 0.0'f32
        var descent = 0.0'f32
        for index in first until end where .boxes[box].items[index].visible
        {
            let extent = .itemExtent(box, index)
            ascent  = Math.max(ascent, extent.ascent)
            descent = Math.max(descent, extent.descent)
        }

        let natural  = ascent + descent
        let height   = Math.max(natural, strutHeight)
        let baseline = top + ascent + Math.max(height - natural, 0) * 0.5

        var lineWidth = 0.0'f32
        for index in first until end where .boxes[box].items[index].visible do
            lineWidth = Math.max(lineWidth, .boxes[box].items[index].x + .boxes[box].items[index].width - left)

        var shift = 0.0'f32
        let extra = Math.max(available - lineWidth, 0)
        switch blockStyle.textAlign
        {
        case .Center: shift = extra * 0.5
        case .Right:  shift = extra
        }

        // Justification stretches the spaces of every line but the one that ends the paragraph.
        var spaceExtra = 0.0'f32
        if blockStyle.textAlign == .Justify and end < .boxes[box].items.count
        {
            var spaces = 0'u32
            for index in first until end where .boxes[box].items[index].visible and .boxes[box].items[index].kind == .Space do
                spaces += 1
            if spaces do
                spaceExtra = extra / cast(f32) spaces
        }

        var slide = 0.0'f32
        for index in first until end
        {
            let item = &.boxes[box].items[index]

            // A run starts on a whole pixel, which is where the painter would snap it anyway;
            // measuring and drawing then agree on where the next run begins.
            item.x = Math.round(item.x + shift + slide)
            if spaceExtra > 0 and item.kind == .Space and item.visible do
                slide += spaceExtra

            item.y = baseline - item.ascent
            if item.kind == .Atomic and item.box != HtmlNoNode do
                item.y = baseline - .boxes[item.box].rect.height

            let style = &.styles[item.style]
            switch style.verticalAlign
            {
            case .Super:  item.y -= item.ascent * 0.32
            case .Sub:    item.y += item.descent * 0.6
            case .Top:    item.y = top
            case .Bottom: item.y = top + height - (item.ascent + item.descent)
            case .Middle: item.y = top + (height - (item.ascent + item.descent)) * 0.5
            }

            if item.kind == .Atomic and item.box != HtmlNoNode
            {
                let target = &.boxes[item.box]
                .translate(item.box, item.x - target.rect.x, item.y - target.rect.y)
            }
        }

        var line: HtmlLineBox
        line.top      = top
        line.height   = height
        line.baseline = baseline
        line.left     = left
        line.width    = lineWidth + shift
        line.first    = cast(u32) first
        line.last     = cast(u32) end
        .boxes[box].lines.add(#move line)
        return height
    }

    // Breaks the inline items of a block into lines and returns the height they took.
    mtd const hasLineContent(box: u32, first, end: u64)->bool
    {
        for index in first until end
        {
            let item = &.boxes[box].items[index]
            switch item.kind
            {
            case .Text, .Space, .Atomic:
                return true

            case .OpenInline, .CloseInline:
                if item.width do
                    return true
            }
        }

        return false
    }

    mtd layoutInline(box: u32, contentX, contentY, contentWidth: f32)->f32
    {
        .boxes[box].lines.clear()

        let styleIndex = .boxes[box].style
        let blockStyle = &.styles[styleIndex]
        let indent     = .resolveLength(blockStyle.textIndent, styleIndex, contentWidth)

        var containing: HtmlContainingBlock
        containing.width = contentWidth

        var y         = contentY
        var lineStart = 0'u64

        // The first line starts further in when the block is indented; the room it loses is the
        // indent itself, so the break test needs no separate limit.
        var pen = contentX + indent

        let count = .boxes[box].items.count
        for index in count
        {
            .boxes[box].items[index].visible = false
            let kind = .boxes[box].items[index].kind
            if kind == .Break
            {
                y         += .finishLine(box, lineStart, index, y, contentX, contentWidth)
                lineStart = index + 1
                pen       = contentX
                continue
            }

            if kind == .Atomic and .boxes[box].items[index].box != HtmlNoNode
            {
                let child     = .boxes[box].items[index].box
                let intrinsic = .intrinsicWidths(child)
                let target    = .styles[.boxes[child].style].width.isAuto() ? Math.clamp(intrinsic.max, 0, contentWidth) : contentWidth
                .layoutBlockBox(child, 0, 0, target, containing)
                .boxes[box].items[index].width = .boxes[child].rect.width
            }

            let width      = .boxes[box].items[index].width
            let itemStyle  = &.styles[.boxes[box].items[index].style]
            let breakable  = itemStyle.whiteSpace != .NoWrap and itemStyle.whiteSpace != .Pre
            let atLineHead = index == lineStart

            // A space that opens a line is collapsed away rather than indenting it.
            if kind == .Space and atLineHead
            {
                lineStart = index + 1
                continue
            }

            if breakable and kind != .Space and !atLineHead and pen + width > contentX + contentWidth + 0.5
            {
                y         += .finishLine(box, lineStart, index, y, contentX, contentWidth)
                lineStart = index
                pen       = contentX
            }

            .boxes[box].items[index].x       = pen
            .boxes[box].items[index].visible = kind != .OpenInline and kind != .CloseInline
            pen += width
        }

        if .hasLineContent(box, lineStart, count) do
            y += .finishLine(box, lineStart, count, y, contentX, contentWidth)
        return Math.max(y - contentY, 0)
    }
}

// Flexible box, grid, and table layout.
private impl HtmlLayout
{
    // Returns the children that take part in a container's own layout.
    mtd flowChildren(box: u32)->Array'u32
    {
        var result: retval
        for child in .boxes[box].children where !.styles[.boxes[child].style].isOutOfFlow() do
            result.add(child)
        return result
    }

    // Lays a flex container out, one line at a time.
    mtd layoutFlex(box: u32, contentX, contentY, contentWidth: f32, containing: HtmlContainingBlock)->f32
    {
        let styleIndex = .boxes[box].style
        let style      = &.styles[styleIndex]
        let items      = .flowChildren(box)
        if items.isEmpty() do
            return 0

        let columnGap = .resolveLength(style.columnGap, styleIndex, contentWidth)
        let rowGap    = .resolveLength(style.rowGap, styleIndex, contentWidth)
        let column    = style.flexDirection == .Column or style.flexDirection == .ColumnReverse

        if column do
            return .layoutFlexColumn(box, items.toSlice(), contentX, contentY, contentWidth, rowGap, containing)

        // The base size of an item is what it asks for before any free space is shared.
        var bases: Array'f32
        for child in items
        {
            let childStyle = &.styles[.boxes[child].style]
            var base: f32
            if !childStyle.flexBasis.isAuto() and !childStyle.flexBasis.isNone() do
                base = .resolveLength(childStyle.flexBasis, .boxes[child].style, contentWidth) + .horizontalExtra(child, contentWidth)
            elif !childStyle.width.isAuto() and !childStyle.width.isNone() do
                base = .resolveLength(childStyle.width, .boxes[child].style, contentWidth) + (childStyle.boxSizing == .BorderBox ? 0 : .horizontalExtra(child, contentWidth))
            else do
                base = .intrinsicWidths(child).max
            bases.add(Math.max(base, 0))
        }

        var y     = contentY
        var start = 0'u64
        while start < items.count
        {
            var end   = start
            var total = 0.0'f32
            while end < items.count
            {
                let next = total + bases[end] + (end > start ? columnGap : 0)
                if style.flexWrap != .NoWrap and end > start and next > contentWidth do
                    break
                total = next
                end   += 1
            }

            y += .layoutFlexLine(box, items.toSlice()[start until end], bases.toSlice()[start until end], contentX, y, contentWidth, total, columnGap, containing)
            if end < items.count do
                y += rowGap
            start = end
        }

        return Math.max(y - contentY, 0)
    }

    // Expands the cross axis of a non-wrapping row flex container after min/explicit height has
    // settled the content box. Multi-line and column containers distribute that room differently.
    mtd expandSingleFlexLine(box: u32, extra, contentWidth: f32)
    {
        if extra <= 0 do
            return
        let style = &.styles[.boxes[box].style]
        if style.flexWrap != .NoWrap or style.flexDirection == .Column or style.flexDirection == .ColumnReverse do
            return

        for child in .boxes[box].children where !.styles[.boxes[child].style].isOutOfFlow()
        {
            let childStyle = &.styles[.boxes[child].style]
            let align      = childStyle.hasAlignSelf ? childStyle.alignSelf : style.alignItems
            switch align
            {
            case .Center:
                .translate(child, 0, extra * 0.5)

            case .End:
                .translate(child, 0, extra)

            case .Stretch:
                if childStyle.height.isAuto()
                {
                    .boxes[child].rect.height    += extra
                    .boxes[child].content.height = Math.max(.boxes[child].rect.height - .verticalExtra(child, contentWidth), 0)
                }
            }
        }
    }

    // Sizes and places one flex line, then aligns it on both axes.
    mtd layoutFlexLine(box: u32, items: const [..] u32, bases: const [..] f32, contentX, lineTop, contentWidth, total, gap: f32, containing: HtmlContainingBlock)->f32
    {
        let style     = &.styles[.boxes[box].style]
        let itemCount = @countof(items)
        let free      = contentWidth - total

        var sizes: Array'f32
        for index in itemCount do
            sizes.add(bases[index])

        if free > 0
        {
            var grow = 0.0'f32
            for child in items do
                grow += .styles[.boxes[child].style].flexGrow
            if grow > 0
            {
                for index in itemCount do
                    sizes[index] += free * .styles[.boxes[items[index]].style].flexGrow / grow
            }
        }
        elif free < 0
        {
            var weight = 0.0'f32
            for index in itemCount do
                weight += .styles[.boxes[items[index]].style].flexShrink * bases[index]
            if weight > 0
            {
                for index in itemCount do
                    sizes[index] = Math.max(sizes[index] + free * .styles[.boxes[items[index]].style].flexShrink * bases[index] / weight, 0)
            }
        }

        var used = 0.0'f32
        for index in itemCount do
            used += sizes[index]
        used += gap * cast(f32) (itemCount > 0 ? itemCount - 1 : 0)

        var extra = Math.max(contentWidth - used, 0)

        // An automatic side margin on a flex item claims what is left before any distribution
        // does, which is how `margin-left: auto` pushes one item against the far edge.
        var autoMargins = 0'u32
        for index in itemCount
        {
            let itemStyle = &.styles[.boxes[items[index]].style]
            if itemStyle.margin.left.isAuto() do
                autoMargins += 1
            if itemStyle.margin.right.isAuto() do
                autoMargins += 1
        }

        var autoShare = 0.0'f32
        if autoMargins and extra > 0
        {
            autoShare = extra / cast(f32) autoMargins
            extra     = 0
        }

        var pen     = contentX
        var between = gap
        switch style.justifyContent
        {
        case .End:
            pen += extra

        case .Center:
            pen += extra * 0.5

        case .SpaceBetween:
            if itemCount > 1 do
                between = gap + extra / cast(f32) (itemCount - 1)

        case .SpaceAround:
            let slot = extra / cast(f32) itemCount
            pen     += slot * 0.5
            between = gap + slot

        case .SpaceEvenly:
            let slot = extra / cast(f32) (itemCount + 1)
            pen     += slot
            between = gap + slot
        }

        var height = 0.0'f32
        for index in itemCount
        {
            let itemStyle = &.styles[.boxes[items[index]].style]
            if itemStyle.margin.left.isAuto() do
                pen += autoShare

            .layoutBlockBox(items[index], pen, lineTop, sizes[index], containing)
            height = Math.max(height, .boxes[items[index]].rect.height)
            pen    += sizes[index] + between
            if itemStyle.margin.right.isAuto() do
                pen += autoShare
        }

        for index in itemCount
        {
            let child      = items[index]
            let childStyle = &.styles[.boxes[child].style]
            let align      = childStyle.hasAlignSelf ? childStyle.alignSelf : style.alignItems
            switch align
            {
            case .Center:
                .translate(child, 0, (height - .boxes[child].rect.height) * 0.5)

            case .End:
                .translate(child, 0, height - .boxes[child].rect.height)

            case .Stretch:
                if childStyle.height.isAuto() and .boxes[child].rect.height < height
                {
                    .boxes[child].rect.height    = height
                    .boxes[child].content.height = Math.max(height - .verticalExtra(child, contentWidth), 0)
                }
            }
        }

        return height
    }

    // Stacks the children of a column flex container and aligns them across the container.
    mtd layoutFlexColumn(box: u32, items: const [..] u32, contentX, contentY, contentWidth, gap: f32, containing: HtmlContainingBlock)->f32
    {
        let style     = &.styles[.boxes[box].style]
        let itemCount = @countof(items)
        var y         = contentY
        for index in itemCount
        {
            let child      = items[index]
            let childStyle = &.styles[.boxes[child].style]
            let align      = childStyle.hasAlignSelf ? childStyle.alignSelf : style.alignItems

            var width = contentWidth
            if align != .Stretch and (childStyle.width.isAuto() or childStyle.width.isNone()) do
                width = Math.clamp(.intrinsicWidths(child).max, 0, contentWidth)

            .layoutBlockBox(child, contentX, y, width, containing)
            switch align
            {
            case .Center: .translate(child, (contentWidth - .boxes[child].rect.width) * 0.5, 0)
            case .End:    .translate(child, contentWidth - .boxes[child].rect.width, 0)
            }

            y = .boxes[child].rect.bottom()
            if index + 1 < itemCount do
                y += gap
        }

        return Math.max(y - contentY, 0)
    }

    // Lays a grid container out over the columns its template declares.
    mtd layoutGrid(box: u32, contentX, contentY, contentWidth: f32, containing: HtmlContainingBlock)->f32
    {
        let styleIndex = .boxes[box].style
        let style      = &.styles[styleIndex]
        let items      = .flowChildren(box)
        if items.isEmpty() do
            return 0

        let columnGap = .resolveLength(style.columnGap, styleIndex, contentWidth)
        let rowGap    = .resolveLength(style.rowGap, styleIndex, contentWidth)

        var widths:    Array'f32
        var fractions: Array'f32
        var fixed = 0.0'f32
        var flex  = 0.0'f32
        for index in style.gridColumnCount
        {
            let node = &.pool.calc[style.gridColumnFirst + index]
            if node.percent > 0
            {
                widths.add(0)
                fractions.add(node.percent)
                flex += node.percent
            }
            else
            {
                let track = node.pixels + node.vw * .viewport.x + node.vh * .viewport.y
                widths.add(track)
                fractions.add(0)
                fixed += track
            }
        }

        if widths.isEmpty()
        {
            widths.add(contentWidth)
            fractions.add(0)
        }

        let gaps = columnGap * cast(f32) (widths.count > 0 ? widths.count - 1 : 0)
        let free = Math.max(contentWidth - fixed - gaps, 0)
        if flex > 0
        {
            for index in widths.count where fractions[index] > 0 do
                widths[index] = free * fractions[index] / flex
        }

        var y     = contentY
        var index = 0'u64
        while index < items.count
        {
            var x      = contentX
            var height = 0.0'f32
            var column = 0'u64
            while column < widths.count and index < items.count
            {
                .layoutBlockBox(items[index], x, y, widths[column], containing)
                height = Math.max(height, .boxes[items[index]].rect.height)
                x      += widths[column] + columnGap
                column += 1
                index  += 1
            }

            y += height
            if index < items.count do
                y += rowGap
        }

        return Math.max(y - contentY, 0)
    }

    // Lays a table out, sizing its columns from what their cells need.
    mtd layoutTable(box: u32, contentX, contentY, contentWidth: f32, containing: HtmlContainingBlock)->f32
    {
        let rows = .flowChildren(box)
        if rows.isEmpty() do
            return 0

        var columns = 0'u64
        for row in rows where .boxes[row].kind == .TableRow do
            columns = Math.max(columns, .boxes[row].children.count)
        if !columns do
            return .layoutBlockChildren(box, contentX, contentY, contentWidth, containing)

        var minimums: Array'f32
        var maximums: Array'f32
        minimums.resize(columns)
        maximums.resize(columns)

        for row in rows where .boxes[row].kind == .TableRow
        {
            let cells = .boxes[row].children
            for index in cells.count
            {
                let intrinsic = .intrinsicWidths(cells[index])
                minimums[index] = Math.max(minimums[index], intrinsic.min)
                maximums[index] = Math.max(maximums[index], intrinsic.max)
            }
        }

        var wanted = 0.0'f32
        var floor  = 0.0'f32
        for index in columns
        {
            wanted += maximums[index]
            floor  += minimums[index]
        }

        var widths: Array'f32
        widths.resize(columns)
        if wanted <= contentWidth or wanted <= floor
        {
            // Everything fits, so the surplus is shared in proportion to what each column asked
            // for, which is what keeps a wide column wide.
            let surplus = Math.max(contentWidth - wanted, 0)
            for index in columns do
                widths[index] = maximums[index] + (wanted > 0 ? surplus * maximums[index] / wanted : surplus / cast(f32) columns)
        }
        else
        {
            let range = wanted - floor
            let room  = Math.max(contentWidth - floor, 0)
            for index in columns do
                widths[index] = minimums[index] + (range > 0 ? room * (maximums[index] - minimums[index]) / range : 0)
        }

        var y = contentY
        for row in rows
        {
            if .boxes[row].kind != .TableRow
            {
                .layoutBlockBox(row, contentX, y, contentWidth, containing)
                y = .boxes[row].rect.bottom()
                continue
            }

            var x      = contentX
            var height = 0.0'f32
            let cells  = .boxes[row].children
            for index in cells.count
            {
                .layoutBlockBox(cells[index], x, y, widths[index], containing)
                height = Math.max(height, .boxes[cells[index]].rect.height)
                x      += widths[index]
            }

            for index in cells.count
            {
                let naturalHeight = .boxes[cells[index]].rect.height
                .boxes[cells[index]].rect.height    = height
                .boxes[cells[index]].content.height = Math.max(height - .verticalExtra(cells[index], contentWidth), 0)

                let extra = height - naturalHeight
                let align = .styles[.boxes[cells[index]].style].verticalAlign
                if align == .Middle do
                    .translateContents(cells[index], 0, extra * 0.5)
                elif align == .Bottom or align == .TextBottom do
                    .translateContents(cells[index], 0, extra)
            }

            .boxes[row].rect    = {contentX, y, contentWidth, height}
            .boxes[row].content = .boxes[row].rect
            y                   += height
        }

        return Math.max(y - contentY, 0)
    }
}
