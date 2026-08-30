#global internal

using Core, Pixel

// One declaration the cascade selected.
//
// `key` packs the whole cascade order into one integer — importance above every specificity,
// specificity above source order, source order above position in its block — so sorting the
// declarations is a plain integer sort.
#[Swag.NoDoc]
public struct HtmlCascadeEntry
{
    key:         u64
    block:       u32
    declaration: u32
}

// A style computed for a generated box rather than for an element.
#[Swag.NoDoc]
public struct HtmlPseudoStyle
{
    element: u32
    which:   HtmlPseudoElement
    style:   HtmlComputedStyle
}

// Computes one style per element, for a whole document.
//
// The pass is a single depth-first walk: a child starts from its parent's inherited values, and
// the custom properties in scope are a stack that grows on the way down and shrinks on the way
// back up. That is what makes `var()` cost nothing to look up and what keeps one style pass
// linear in the number of elements.
#[Swag.NoDoc]
public struct HtmlStyleResolver
{
    #[Swag.Late]
    {
        document: *HtmlDocument
        sheet:    *HtmlStyleSheet
        pool:     *HtmlValuePool
    }

    defaults: HtmlStyleDefaults

    styles:      Array'HtmlComputedStyle
    nodeStyles:  Array'u32
    pseudos:     Array'HtmlPseudoStyle
    pseudoIndex: HashTable'(u64, u32)

    media:    Array'bool
    match:    HtmlMatchContext
    viewport: Math.Point

    customNames:  Array'String
    customValues: Array'String
    candidates:   Array'u32
    entries:      Array'HtmlCascadeEntry
}

impl HtmlStyleResolver
{
    // Expands every `var()` reference of a declaration value.
    //
    // A reference resolves against the properties in scope at the element being styled, and its
    // own value may reference another one, so substitution repeats until the text settles.
    mtd const resolveVariables(value: string)->String
    {
        // A cyclic definition would otherwise substitute forever; CSS treats one as invalid.
        const MaxSubstitutionRounds = 8'u32

        var current = String.from(value)
        for MaxSubstitutionRounds
        {
            let start = Utf8.indexOf(current.toString(), "var(")
            if start == Swag.U64.Max do
                break

            var scan     = start + 3
            let argument = htmlReadBalanced(current.toString(), &scan)
            let comma    = Utf8.indexOf(argument, ','rune)
            let name     = Latin1.trim(comma == Swag.U64.Max ? argument : argument[0 until comma])
            let fallback = comma == Swag.U64.Max ? "" : Latin1.trim(argument[comma + 1 to])

            var replacement = String.from(fallback)
            for index in .customNames.count
            {
                let candidate = .customNames.count - index - 1
                if .customNames[candidate].toString() != name do
                    continue
                replacement = .customValues[candidate]
                break
            }

            var next = String.from(current.toString()[0 until start])
            next    += replacement
            next    += current.toString()[scan to]
            current = #move next
        }

        return current
    }

    // Applies the built-in presentation of an element, which is what a browser draws before any
    // stylesheet has a say.
    private mtd applyUserAgent(style: *HtmlComputedStyle, element: u32, context: *HtmlDeclarationContext)
    {
        let node   = .document.constNode(element)
        let parent = context.length.fontSize

        switch node.tag
        {
        case .Html, .Div, .Section, .Article, .Aside, .Nav, .Header, .Footer, .Main,
             .HGroup, .Address, .FieldSet, .Form, .Details, .Summary, .FigCaption, .Legend,
             .Dt, .Dd, .Output, .Picture:
            style.display = .Block

        case .Body:

            // The eight pixels every browser puts around a page body are what keeps a document
            // with no stylesheet of its own off the window edge.
            style.display = .Block
            style.margin.setAll(HtmlLength.pixels(8))

        case .P:
            style.display       = .Block
            style.margin.top    = HtmlLength.pixels(parent)
            style.margin.bottom = HtmlLength.pixels(parent)

        case .H1:
            style.display       = .Block
            style.fontSize      = parent * 2
            style.fontWeight    = 700
            style.margin.top    = HtmlLength.pixels(style.fontSize * 0.67)
            style.margin.bottom = HtmlLength.pixels(style.fontSize * 0.67)

        case .H2:
            style.display       = .Block
            style.fontSize      = parent * 1.5
            style.fontWeight    = 700
            style.margin.top    = HtmlLength.pixels(style.fontSize * 0.83)
            style.margin.bottom = HtmlLength.pixels(style.fontSize * 0.83)

        case .H3:
            style.display       = .Block
            style.fontSize      = parent * 1.17
            style.fontWeight    = 700
            style.margin.top    = HtmlLength.pixels(style.fontSize)
            style.margin.bottom = HtmlLength.pixels(style.fontSize)

        case .H4:
            style.display       = .Block
            style.fontWeight    = 700
            style.margin.top    = HtmlLength.pixels(style.fontSize * 1.33)
            style.margin.bottom = HtmlLength.pixels(style.fontSize * 1.33)

        case .H5:
            style.display       = .Block
            style.fontSize      = parent * 0.83
            style.fontWeight    = 700
            style.margin.top    = HtmlLength.pixels(style.fontSize * 1.67)
            style.margin.bottom = HtmlLength.pixels(style.fontSize * 1.67)

        case .H6:
            style.display       = .Block
            style.fontSize      = parent * 0.67
            style.fontWeight    = 700
            style.margin.top    = HtmlLength.pixels(style.fontSize * 2.33)
            style.margin.bottom = HtmlLength.pixels(style.fontSize * 2.33)

        case .Ul, .Ol, .Menu:
            style.display       = .Block
            style.margin.top    = HtmlLength.pixels(parent)
            style.margin.bottom = HtmlLength.pixels(parent)
            style.padding.left  = HtmlLength.pixels(40)
            style.listStyleType = node.tag == .Ol ? .Decimal : .Disc

            // A nested list sits inside its item, and browsers drop its vertical margins so the
            // outline reads as one block instead of a run of separated paragraphs.
            let owner = .document.constNode(element).parent
            if owner != HtmlNoNode and .document.constNode(owner).tag == .Li
            {
                style.margin.top    = HtmlLength.pixels(0)
                style.margin.bottom = HtmlLength.pixels(0)
            }

        case .Li:
            style.display = .ListItem

        case .Dl:
            style.display       = .Block
            style.margin.top    = HtmlLength.pixels(parent)
            style.margin.bottom = HtmlLength.pixels(parent)

        case .Blockquote, .Figure:
            style.display       = .Block
            style.margin.top    = HtmlLength.pixels(parent)
            style.margin.bottom = HtmlLength.pixels(parent)
            style.margin.left   = HtmlLength.pixels(40)
            style.margin.right  = HtmlLength.pixels(40)

        case .Pre:
            style.display       = .Block
            style.fontFamily    = .Mono
            style.whiteSpace    = .Pre
            style.margin.top    = HtmlLength.pixels(parent)
            style.margin.bottom = HtmlLength.pixels(parent)

        case .Hr:
            style.display            = .Block
            style.margin.top         = HtmlLength.pixels(parent * 0.5)
            style.margin.bottom      = HtmlLength.pixels(parent * 0.5)
            style.borderTop.width    = 1
            style.borderTop.style    = .Solid
            style.borderTop.color    = .defaults.border
            style.borderTop.hasColor = true

        case .Code, .Kbd, .Samp, .Var:
            style.fontFamily = .Mono

        case .B, .Strong:
            style.fontWeight = 700

        case .I, .Em, .Cite, .Dfn:
            style.italic = true

        case .Small:
            style.fontSize = parent * 0.8

        case .Sub:
            style.fontSize      = parent * 0.8
            style.verticalAlign = .Sub

        case .Sup:
            style.fontSize      = parent * 0.8
            style.verticalAlign = .Super

        case .Mark:
            style.background = Color.fromArgb(0xFFFFFF00)
            style.color      = Color.fromArgb(0xFF000000)

        case .S, .Del:
            style.textDecoration.add(.LineThrough)

        case .U, .Ins:
            style.textDecoration.add(.Underline)

        case .A:
            if .document.hasAttribute(element, "href")
            {
                style.color = .defaults.link
                style.textDecoration.add(.Underline)
                style.cursorPointer = true
            }

        case .Table:
            style.display = .Table

        case .TBody, .THead, .TFoot:
            style.display = .TableRowGroup

        case .Tr:
            style.display = .TableRow

        case .Td:
            style.display = .TableCell
            style.padding.setAll(HtmlLength.pixels(1))

        case .Th:
            style.display    = .TableCell
            style.fontWeight = 700
            style.textAlign  = .Center
            style.padding.setAll(HtmlLength.pixels(1))

        case .Caption:
            style.display   = .TableCaption
            style.textAlign = .Center

        case .Img, .Button, .Select, .TextArea, .Progress, .Embed, .Canvas, .Video, .Object, .IFrame:
            style.display = .InlineBlock

        case .Input:
            style.display = .InlineBlock
            let kind = .document.attribute(element, "type")
            if kind == "checkbox" or kind == "radio"
            {
                style.width  = HtmlLength.pixels(13)
                style.height = HtmlLength.pixels(13)
                style.margin.setAll(HtmlLength.pixels(3))
                style.borderTop.width    = 1
                style.borderTop.style    = .Solid
                style.borderTop.color    = .defaults.border
                style.borderTop.hasColor = true
                style.borderRight        = style.borderTop
                style.borderBottom       = style.borderTop
                style.borderLeft         = style.borderTop
            }

        case .ColGroup, .Col:
            style.display = .TableColumnGroup

        case .Head, .Style, .Script, .Title, .Meta, .Link, .Template, .Base, .Param, .Source, .Track:
            style.display = .None

        case .Span, .Label, .Abbr, .Time, .Q, .Ruby, .Rt, .Rp, .NoScript, .Svg, .Br, .Wbr:
            style.display = .Inline
        }

        // A closed disclosure shows its summary and nothing else. The rule belongs here rather
        // than in the box builder, because a document is free to override it.
        let container = .document.constNode(element).parent
        if container != HtmlNoNode and .document.constNode(container).tag == .Details
        {
            if node.tag != .Summary and !.document.hasAttribute(container, "open") do
                style.display = .None
        }

        // Legacy documents and repository landing pages still use presentational attributes.
        // Apply them before author CSS so an ordinary style rule keeps precedence.
        let align = .document.attribute(element, "align")
        if Utf8.compare(align, "left", .Latin1NoCase) == 0 do
            style.textAlign = .Left
        elif Utf8.compare(align, "center", .Latin1NoCase) == 0 do
            style.textAlign = .Center
        elif Utf8.compare(align, "right", .Latin1NoCase) == 0 do
            style.textAlign = .Right
        elif Utf8.compare(align, "justify", .Latin1NoCase) == 0 do
            style.textAlign = .Justify

        if node.tag == .Img
        {
            let width = .document.attribute(element, "width")
            if width.count do
                style.applyDeclaration(.Width, width, context)
            let height = .document.attribute(element, "height")
            if height.count do
                style.applyDeclaration(.Height, height, context)
        }

        context.length.fontSize = style.fontSize
    }

    // Selects, among the rules that can apply to an element, those that describe it.
    //
    // The candidate list is gathered once per element and read three times — for the element and
    // for each of its two generated boxes — because gathering it is the expensive half.
    private mtd collect(element: u32, pseudo: HtmlPseudoElement)
    {
        .entries.clear()

        var previous = HtmlNoNode
        for rule in .candidates
        {
            if rule == previous do
                continue
            previous = rule

            let source = &.sheet.rules[rule]
            if source.parts.backPtr().pseudoElement != pseudo do
                continue
            if !.sheet.matches(source, element, &.match) do
                continue

            let block = &.sheet.blocks[source.block]
            for index in block.declarations.count
            {
                var entry: HtmlCascadeEntry
                entry.block       = source.block
                entry.declaration = cast(u32) index
                entry.key         = HtmlStyleResolver.cascadeKey(block.declarations[index].important, source.specificity, source.order, cast(u32) index)
                .entries.add(entry)
            }
        }

        .entries.sort(func||(a, b) { return a.key <=> b.key })
    }

    // Packs one declaration's cascade weight, most significant criterion first.
    func cascadeKey(important: bool, specificity, order, position: u32)->u64
    {
        var result = important ? 1'u64 << 63 : 0'u64
        result |= cast(u64) (specificity & 0x7FFFFF) << 40
        result |= cast(u64) (order & 0xFFFFFFF) << 12
        result |= cast(u64) (position & 0xFFF)
        return result
    }

    // Applies the sorted declarations, in the three rounds the language requires: the custom
    // properties they may reference, then the font size every relative length depends on, then
    // everything else.
    private mtd applyEntries(style: *HtmlComputedStyle, context: *HtmlDeclarationContext, inlineBlock: #null const *HtmlDeclarationBlock)->u64
    {
        var pushed = 0'u64
        for entry in .entries
        {
            let declaration = &.sheet.blocks[entry.block].declarations[entry.declaration]
            if declaration.property != .Custom do
                continue
            .customNames.add(declaration.name)
            .customValues.add(.resolveVariables(declaration.value.toString()))
            pushed += 1
        }

        if inlineBlock
        {
            for value in inlineBlock.declarations where value.property == .Custom
            {
                .customNames.add(value.name)
                .customValues.add(.resolveVariables(value.value.toString()))
                pushed += 1
            }
        }

        for entry in .entries
        {
            let declaration = &.sheet.blocks[entry.block].declarations[entry.declaration]
            if declaration.property == .FontSize do
                .apply(style, context, declaration)
        }

        if inlineBlock
        {
            for value in inlineBlock.declarations where value.property == .FontSize do
                .apply(style, context, value)
        }

        for entry in .entries
        {
            let declaration = &.sheet.blocks[entry.block].declarations[entry.declaration]
            if declaration.property != .FontSize and declaration.property != .Custom do
                .apply(style, context, declaration)
        }

        if inlineBlock
        {
            for value in inlineBlock.declarations where value.property != .FontSize and value.property != .Custom do
                .apply(style, context, value)
        }

        return pushed
    }

    // Applies one declaration, expanding its custom-property references only when it has any.
    private mtd apply(style: *HtmlComputedStyle, context: *HtmlDeclarationContext, declaration: const *HtmlDeclaration)
    {
        let value = declaration.value.toString()
        if !Utf8.contains(value, "var(")
        {
            style.applyDeclaration(declaration.property, value, context)
            return
        }

        style.applyDeclaration(declaration.property, .resolveVariables(value).toString(), context)
    }

    // Computes the style of one generated box, and records it when the selector asked for one.
    private mtd resolvePseudo(element: u32, which: HtmlPseudoElement, parentStyle: HtmlComputedStyle)
    {
        .collect(element, which)
        if .entries.isEmpty() do
            return

        var style = HtmlComputedStyle.inherited(parentStyle)
        style.display = .Inline

        var context: HtmlDeclarationContext
        context.pool                  = .pool
        context.defaults              = .defaults
        context.length.fontSize       = parentStyle.fontSize
        context.length.rootFontSize   = .defaults.fontSize
        context.length.viewportWidth  = .viewport.x
        context.length.viewportHeight = .viewport.y

        let pushed = .applyEntries(&style, &context, null)
        for pushed
        {
            .customNames.removeBack()
            .customValues.removeBack()
        }

        if !style.hasContent or style.display == .None do
            return

        var record: HtmlPseudoStyle
        record.element = element
        record.which   = which
        record.style   = style
        .pseudoIndex.add(HtmlStyleResolver.pseudoKey(element, which), cast(u32) .pseudos.count)
        .pseudos.add(#move record)
    }

    func pseudoKey(element: u32, which: HtmlPseudoElement)->u64 => (cast(u64) element << 8) | cast(u64) which

    // Computes the style of one element and of every descendant.
    private mtd resolveElement(element: u32, parentStyle: HtmlComputedStyle)
    {
        var style = HtmlComputedStyle.inherited(parentStyle)

        var context: HtmlDeclarationContext
        context.pool                  = .pool
        context.defaults              = .defaults
        context.length.fontSize       = parentStyle.fontSize
        context.length.rootFontSize   = .defaults.fontSize
        context.length.viewportWidth  = .viewport.x
        context.length.viewportHeight = .viewport.y

        .applyUserAgent(&style, element, &context)

        var inlineBlock: HtmlDeclarationBlock
        let inlineText = .document.attribute(element, "style")
        if inlineText.count do
            inlineBlock = HtmlStyleSheet.parseDeclarations(inlineText)

        .sheet.candidates(.document, element, &.candidates)
        .collect(element, .None)
        let pushed = .applyEntries(&style, &context, inlineBlock.declarations.isEmpty() ? null : &inlineBlock)

        // An inline box has no room of its own for vertical margins, so the flow ignores them.
        if style.display == .Inline
        {
            style.margin.top    = HtmlLength.pixels(0)
            style.margin.bottom = HtmlLength.pixels(0)
        }

        .nodeStyles[element] = cast(u32) .styles.count
        .styles.add(style)

        // Both generated boxes are resolved before the children, while the candidate list still
        // describes this element and its custom properties are still in scope.
        .resolvePseudo(element, .Before, style)
        .resolvePseudo(element, .After, style)

        for child in .document.constNode(element).children where .document.constNode(child).kind == .Element do
            .resolveElement(child, style)

        for pushed
        {
            .customNames.removeBack()
            .customValues.removeBack()
        }
    }

    // Recomputes every style, which is what a new document, a resize, or a theme change needs.
    mtd resolve(document: *HtmlDocument, sheet: *HtmlStyleSheet, pool: *HtmlValuePool, defaults: HtmlStyleDefaults, viewport: Math.Point, darkScheme: bool)
    {
        .document = document
        .sheet    = sheet
        .pool     = pool
        .defaults = defaults
        .viewport = viewport

        var state: HtmlMediaState
        state.viewportWidth  = viewport.x
        state.viewportHeight = viewport.y
        state.darkScheme     = darkScheme
        .media               = sheet.evaluateMedia(state)

        .match.prepare(document)
        .match.mediaOn = .media

        .customNames.clear()
        .customValues.clear()
        .pseudos.clear()
        .pseudoIndex.clear()
        .styles.clear()
        .styles.reserve(.match.numElements + 1)
        .nodeStyles.clear()
        .nodeStyles.resize(document.nodes.count)
        .nodeStyles.fill(HtmlNoNode)

        let root = HtmlComputedStyle.fromDefaults(defaults)
        .nodeStyles[0] = 0
        .styles.add(root)
        for child in document.constNode(0).children where document.constNode(child).kind == .Element do
            .resolveElement(child, root)
    }

    // Returns the style of a generated box, or null when the document generates none there.
    mtd const pseudoStyle(element: u32, which: HtmlPseudoElement)->#null const *HtmlComputedStyle
    {
        let found = .pseudoIndex.tryFind(HtmlStyleResolver.pseudoKey(element, which))
        if !found do
            return null
        return &.pseudos[found!.value].style
    }
}
