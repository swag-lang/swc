#global internal

using Core

// Index meaning "no node". A document always owns node 0, so zero is a valid index.
//
// The engine types are exported with [[Gui.HtmlView]], which carries them as fields, so the value
// their defaults name has to travel with them.
#[Swag.NoDoc]
public const HtmlNoNode = Swag.U32.Max

// The elements the engine treats specially.
//
// An element outside this set still parses, styles, and lays out; the enum exists so the parser,
// the user-agent stylesheet, and the layout engine test an integer instead of a string.
#[Swag.NoDoc]
public enum HtmlTag
{
    Unknown
    A
    Abbr
    Address
    Area
    Article
    Aside
    B
    Base
    Blockquote
    Body
    Br
    Button
    Canvas
    Caption
    Cite
    Code
    Col
    ColGroup
    Dd
    Del
    Details
    Dfn
    Div
    Dl
    Dt
    Em
    Embed
    FieldSet
    FigCaption
    Figure
    Footer
    Form
    H1
    H2
    H3
    H4
    H5
    H6
    Head
    Header
    HGroup
    Hr
    Html
    I
    IFrame
    Img
    Input
    Ins
    Kbd
    Label
    Legend
    Li
    Link
    Main
    Mark
    Menu
    Meta
    Nav
    NoScript
    Object
    Ol
    OptGroup
    Option
    Output
    P
    Param
    Picture
    Pre
    Progress
    Q
    Rp
    Rt
    Ruby
    S
    Samp
    Script
    Section
    Select
    Small
    Source
    Span
    Strong
    Style
    Sub
    Summary
    Sup
    Svg
    Table
    TBody
    Td
    Template
    TextArea
    TFoot
    Th
    THead
    Time
    Title
    Tr
    Track
    U
    Ul
    Var
    Video
    Wbr
}

// What a node contributes to the tree.
#[Swag.NoDoc]
public enum HtmlNodeKind
{
    Document
    Element
    Text
}

// One parsed attribute, with its name folded to lower case and its value entity-decoded.
//
// Both are runs of the document's text pool: a page carries hundreds of thousands of attributes,
// and an owning string costs seven times what a run costs.
#[Swag.NoDoc]
public struct HtmlAttribute
{
    name:  HtmlRange
    value: HtmlRange
}

// A contiguous run of entries inside one of the document's pools.
//
// A run of text addresses the source the document keeps, unless its top bit says it addresses the
// pool of text the source does not spell — a folded name, a run with a character reference in it.
// That is what lets the overwhelming majority of a page's text, attribute values and names cost
// nothing but the two numbers naming them.
#[Swag.NoDoc]
public struct HtmlRange
{
    start: u32
    count: u32
}

// Marks a run as addressing the built text rather than the source.
#[Swag.NoDoc]
public const HtmlBuiltText = 0x8000_0000'u32

// One node of the parsed tree.
//
// Every link is an index into the owning document, so the node array can grow without
// invalidating anything a caller holds.
//
// A node is deliberately narrow, because a large page holds hundreds of thousands of them and
// the cost of parsing one is dominated by the memory it touches. What only some nodes need lives
// beside the tree: attributes and classes are runs inside the document's pools, an element's name
// comes from its tag, and `text` carries the content of a text node or the raw name of an element
// whose tag this engine does not know. Children are a chain rather than an array per node, which
// is what makes an element cost no allocation at all; walk them with [[HtmlDocument.children]].
#[Swag.NoDoc]
public struct HtmlNode
{
    kind:         HtmlNodeKind
    tag:          HtmlTag
    text:         HtmlRange
    parent      = HtmlNoNode
    firstChild  = HtmlNoNode
    lastChild   = HtmlNoNode
    nextSibling = HtmlNoNode
    prevSibling = HtmlNoNode
    sourceOffset: u64
    attributes:   HtmlRange
    classes:      HtmlRange
}

// The children of one node, in order.
//
// A cursor rather than a container: the chain lives in the nodes themselves, and nothing may add
// a node while one of these is being walked.
#[Swag.NoDoc]
public struct HtmlChildren
{
    document: const *HtmlDocument = undefined
    first = HtmlNoNode
}

impl HtmlChildren
{
    #[Macro]
    func(ptr: bool) opVisit(const me, stmt: #code(item, index: u64))
        where !ptr
    {
        var node  = .first
        var visit = 0'u64
        while node != HtmlNoNode
        {
            // The cursor advances before the body runs, so a `continue` in the body reaches the
            // next child instead of the same one, and a body that unlinks the node it was handed
            // still walks the rest of the chain.
            let current  = node
            let visitIdx = visit
            node  = .document.constNode(node).nextSibling
            visit += 1
            #inject(stmt, item = current, index = visitIdx)
        }
    }
}

// A parsed HTML tree.
//
// Node 0 is always the document node and never has a parent. The tree keeps the source offset of
// every node so a viewer can map a byte position in the file back to what is drawn for it.
//
// Attributes and classes live in pools rather than in per-node arrays: an element's attributes
// are written consecutively as its start tag is read, so one run of the pool is all a node has to
// remember, and the tree costs two allocations instead of three per element.
#[Swag.NoDoc]
public struct HtmlDocument
{
    nodes:         Array'HtmlNode
    attributePool: Array'HtmlAttribute
    classPool:     Array'HtmlRange
    sourceText:    String
    builtText:     String
}

impl HtmlDocument
{
    // Resolves an element name to its interned tag.
    //
    // The names are grouped by length first: a `switch` over strings tests its cases in order, so
    // a name answers against the handful of tags that could possibly match it rather than against
    // all of them. Measured on a page's 147k elements, that is 24 ns per name instead of 40.
    func tagFromName(name: string)->HtmlTag
    {
        switch @countof(name)
        {
        case 1:
            switch name
            {
            case "a": return .A
            case "b": return .B
            case "i": return .I
            case "p": return .P
            case "q": return .Q
            case "s": return .S
            case "u": return .U
            }

        case 2:
            switch name
            {
            case "br": return .Br
            case "dd": return .Dd
            case "dl": return .Dl
            case "dt": return .Dt
            case "em": return .Em
            case "h1": return .H1
            case "h2": return .H2
            case "h3": return .H3
            case "h4": return .H4
            case "h5": return .H5
            case "h6": return .H6
            case "hr": return .Hr
            case "li": return .Li
            case "ol": return .Ol
            case "rp": return .Rp
            case "rt": return .Rt
            case "td": return .Td
            case "th": return .Th
            case "tr": return .Tr
            case "ul": return .Ul
            }

        case 3:
            switch name
            {
            case "col": return .Col
            case "del": return .Del
            case "dfn": return .Dfn
            case "div": return .Div
            case "img": return .Img
            case "ins": return .Ins
            case "kbd": return .Kbd
            case "nav": return .Nav
            case "pre": return .Pre
            case "sub": return .Sub
            case "sup": return .Sup
            case "svg": return .Svg
            case "var": return .Var
            case "wbr": return .Wbr
            }

        case 4:
            switch name
            {
            case "abbr": return .Abbr
            case "area": return .Area
            case "base": return .Base
            case "body": return .Body
            case "cite": return .Cite
            case "code": return .Code
            case "form": return .Form
            case "head": return .Head
            case "html": return .Html
            case "link": return .Link
            case "main": return .Main
            case "mark": return .Mark
            case "menu": return .Menu
            case "meta": return .Meta
            case "ruby": return .Ruby
            case "samp": return .Samp
            case "span": return .Span
            case "time": return .Time
            }

        case 5:
            switch name
            {
            case "aside": return .Aside
            case "embed": return .Embed
            case "input": return .Input
            case "label": return .Label
            case "param": return .Param
            case "small": return .Small
            case "style": return .Style
            case "table": return .Table
            case "tbody": return .TBody
            case "tfoot": return .TFoot
            case "thead": return .THead
            case "title": return .Title
            case "track": return .Track
            case "video": return .Video
            }

        case 6:
            switch name
            {
            case "button": return .Button
            case "canvas": return .Canvas
            case "figure": return .Figure
            case "footer": return .Footer
            case "header": return .Header
            case "hgroup": return .HGroup
            case "iframe": return .IFrame
            case "legend": return .Legend
            case "object": return .Object
            case "option": return .Option
            case "output": return .Output
            case "script": return .Script
            case "select": return .Select
            case "source": return .Source
            case "strong": return .Strong
            }

        case 7:
            switch name
            {
            case "address": return .Address
            case "article": return .Article
            case "caption": return .Caption
            case "details": return .Details
            case "picture": return .Picture
            case "section": return .Section
            case "summary": return .Summary
            }

        case 8:
            switch name
            {
            case "colgroup": return .ColGroup
            case "fieldset": return .FieldSet
            case "noscript": return .NoScript
            case "optgroup": return .OptGroup
            case "progress": return .Progress
            case "template": return .Template
            case "textarea": return .TextArea
            }

        case 10:
            switch name
            {
            case "blockquote": return .Blockquote
            case "figcaption": return .FigCaption
            }
        }

        return .Unknown
    }

    // Returns the lower-case name of an interned tag, which is the spelling `tagFromName` reads.
    func tagName(tag: HtmlTag)->string
    {
        switch tag
        {
        case .A:          return "a"
        case .Abbr:       return "abbr"
        case .Address:    return "address"
        case .Area:       return "area"
        case .Article:    return "article"
        case .Aside:      return "aside"
        case .B:          return "b"
        case .Base:       return "base"
        case .Blockquote: return "blockquote"
        case .Body:       return "body"
        case .Br:         return "br"
        case .Button:     return "button"
        case .Canvas:     return "canvas"
        case .Caption:    return "caption"
        case .Cite:       return "cite"
        case .Code:       return "code"
        case .Col:        return "col"
        case .ColGroup:   return "colgroup"
        case .Dd:         return "dd"
        case .Del:        return "del"
        case .Details:    return "details"
        case .Dfn:        return "dfn"
        case .Div:        return "div"
        case .Dl:         return "dl"
        case .Dt:         return "dt"
        case .Em:         return "em"
        case .Embed:      return "embed"
        case .FieldSet:   return "fieldset"
        case .FigCaption: return "figcaption"
        case .Figure:     return "figure"
        case .Footer:     return "footer"
        case .Form:       return "form"
        case .H1:         return "h1"
        case .H2:         return "h2"
        case .H3:         return "h3"
        case .H4:         return "h4"
        case .H5:         return "h5"
        case .H6:         return "h6"
        case .Head:       return "head"
        case .Header:     return "header"
        case .HGroup:     return "hgroup"
        case .Hr:         return "hr"
        case .Html:       return "html"
        case .I:          return "i"
        case .IFrame:     return "iframe"
        case .Img:        return "img"
        case .Input:      return "input"
        case .Ins:        return "ins"
        case .Kbd:        return "kbd"
        case .Label:      return "label"
        case .Legend:     return "legend"
        case .Li:         return "li"
        case .Link:       return "link"
        case .Main:       return "main"
        case .Mark:       return "mark"
        case .Menu:       return "menu"
        case .Meta:       return "meta"
        case .Nav:        return "nav"
        case .NoScript:   return "noscript"
        case .Object:     return "object"
        case .Ol:         return "ol"
        case .OptGroup:   return "optgroup"
        case .Option:     return "option"
        case .Output:     return "output"
        case .P:          return "p"
        case .Param:      return "param"
        case .Picture:    return "picture"
        case .Pre:        return "pre"
        case .Progress:   return "progress"
        case .Q:          return "q"
        case .Rp:         return "rp"
        case .Rt:         return "rt"
        case .Ruby:       return "ruby"
        case .S:          return "s"
        case .Samp:       return "samp"
        case .Script:     return "script"
        case .Section:    return "section"
        case .Select:     return "select"
        case .Small:      return "small"
        case .Source:     return "source"
        case .Span:       return "span"
        case .Strong:     return "strong"
        case .Style:      return "style"
        case .Sub:        return "sub"
        case .Summary:    return "summary"
        case .Sup:        return "sup"
        case .Svg:        return "svg"
        case .Table:      return "table"
        case .TBody:      return "tbody"
        case .Td:         return "td"
        case .Template:   return "template"
        case .TextArea:   return "textarea"
        case .TFoot:      return "tfoot"
        case .Th:         return "th"
        case .THead:      return "thead"
        case .Time:       return "time"
        case .Title:      return "title"
        case .Tr:         return "tr"
        case .Track:      return "track"
        case .U:          return "u"
        case .Ul:         return "ul"
        case .Var:        return "var"
        case .Video:      return "video"
        case .Wbr:        return "wbr"
        }

        return ""
    }

    // Reports whether an element never has content or an end tag.
    func isVoidTag(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .Area, .Base, .Br, .Col, .Embed, .Hr, .Img, .Input, .Link, .Meta, .Param, .Source, .Track, .Wbr: return true
        }

        return false
    }

    // Reports whether an element's content is text that never contains markup.
    func isRawTextTag(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .Script, .Style, .TextArea, .Title: return true
        }

        return false
    }

    // Reports whether an element's content never becomes part of the rendered document.
    //
    // The engine executes nothing, so a script body, a template, and an embedded document are
    // parsed only far enough to be skipped.
    func isSkippedTag(tag: HtmlTag)->bool
    {
        switch tag
        {
        case .Script, .Template, .IFrame, .Object, .Canvas, .Video, .Svg: return true
        }

        return false
    }

    // Prepares an empty tree holding only its document node.
    func create()->HtmlDocument
    {
        var result: retval
        var root:   HtmlNode
        root.kind = .Document
        result.nodes.add(#move root)
        return result
    }

    // Releases every node while keeping the document node.
    mtd clear()
    {
        .nodes.clear()
        .attributePool.clear()
        .classPool.clear()
        .sourceText.clear()
        .builtText.clear()
        var root: HtmlNode
        root.kind = .Document
        .nodes.add(#move root)
    }

    // Appends fed source to the document and returns where it landed.
    //
    // The source stays for the life of the document: it is what every run of text addresses, and
    // it is never rewritten, so the offsets stay valid however the parser is fed.
    mtd appendSource(chunk: string)->u64
    {
        let result = .sourceText.length
        .sourceText += chunk
        return result
    }

    // Returns the whole source read so far.
    mtd const source()->string => .sourceText.toString()

    // Returns the run a stretch of source occupies, which is the common case: text the document
    // spells the way it is stored.
    func sourceRange(start, count: u64)->HtmlRange => {cast(u32) start, cast(u32) count}

    // Copies text the source does not spell — a folded name, a decoded run — and returns where it
    // landed. A run built this way is addressed by offset, so a slice read back from it is
    // invalidated by the next call.
    mtd intern(text: string)->HtmlRange
    {
        var result: retval
        result.start = cast(u32) .builtText.length | HtmlBuiltText
        result.count = cast(u32) @countof(text)
        .builtText   += text
        return result
    }

    // Copies a run and folds it to lower case in place, which is what a tag or attribute name the
    // source wrote in mixed case is stored as.
    mtd internLower(text: string)->HtmlRange
    {
        let result = .intern(text)
        let start  = result.start ^ HtmlBuiltText
        let buffer = .builtText.buffer!
        for index in result.count do
            buffer[start + index] = Latin1.toLower(buffer[start + index])
        return result
    }

    // Copies a run of source text, resolving the character references it carries.
    mtd internDecoded(text: string, inAttribute = false)->HtmlRange
    {
        var result: retval
        result.start = cast(u32) .builtText.length | HtmlBuiltText
        htmlDecodeInto(&.builtText, text, inAttribute)
        result.count = cast(u32) .builtText.length - (result.start ^ HtmlBuiltText)
        return result
    }

    // Returns the text a run holds.
    mtd const text(range: HtmlRange)->string
    {
        if range.start & HtmlBuiltText
        {
            let start = range.start ^ HtmlBuiltText
            return .builtText.toString()[start until start + range.count]
        }

        return .sourceText.toString()[range.start until range.start + range.count]
    }

    // Returns the text a node holds: the content of a text node, or nothing for an element.
    mtd const textOf(index: u32)->string => .text(.nodes[index].text)

    // Reserves the storage a source of that size is expected to need.
    //
    // The estimate is deliberately low: a markup-dense page runs at about twenty bytes of source
    // per node, a prose page at several hundred, and reserving for the dense end would multiply
    // the footprint of the other. What it removes is the long series of early reallocations of an
    // array that ends up tens of megabytes long.
    mtd reserveForSource(bytes: u64)
    {
        const SourceBytesPerNode = 48'u64
        const MaxReservedNodes   = 4_000_000'u64
        const MaxReservedText    = 64 * 1024 * 1024'u64

        // Only ever grows: `reserve` empties an array when it is asked for nothing, and truncates
        // a string to what it is asked to hold.
        let nodes = Math.min(bytes / SourceBytesPerNode, MaxReservedNodes)
        if nodes > .nodes.capacity do
            .nodes.reserve(nodes)

        let source = Math.min(bytes, MaxReservedText)
        if source > .sourceText.capacity do
            .sourceText.reserve(source)
    }

    // Returns the children of a node, in order.
    mtd const children(node: u32)->HtmlChildren => {me, .nodes[node].firstChild}

    // Returns how many children a node has. A caller that only asks whether there are any tests
    // `firstChild` instead, which costs nothing.
    mtd const childCount(node: u32)->u64
    {
        var result = 0'u64
        for child in .children(node) do
            result += 1
        return result
    }

    // Returns the nth child of a node, or `HtmlNoNode`.
    mtd const childAt(node: u32, wanted: u64)->u32
    {
        for child, index in .children(node) where index == wanted do
            return child
        return HtmlNoNode
    }

    // Appends a node to a parent's chain of children.
    private mtd linkChild(parent, child: u32)
    {
        let last = .nodes[parent].lastChild
        .nodes[child].parent      = parent
        .nodes[child].prevSibling = last
        if last != HtmlNoNode do
            .nodes[last].nextSibling = child
        else do
            .nodes[parent].firstChild = child
        .nodes[parent].lastChild = child
    }

    // Inserts a node in front of one of its parent's children.
    private mtd linkBefore(sibling, child: u32)
    {
        let parent   = .nodes[sibling].parent
        let previous = .nodes[sibling].prevSibling
        .nodes[child].parent        = parent
        .nodes[child].prevSibling   = previous
        .nodes[child].nextSibling   = sibling
        .nodes[sibling].prevSibling = child
        if previous != HtmlNoNode do
            .nodes[previous].nextSibling = child
        else do
            .nodes[parent].firstChild = child
    }

    mtd node(index: u32)->*HtmlNode => &.nodes[index]

    mtd const constNode(index: u32)->const *HtmlNode => &.nodes[index]

    // Appends an element under `parent` and returns its index.
    //
    // The caller hands over the folded name and the tag it already resolved from it: the parser
    // needs that tag before the node exists, and resolving a name is a string comparison per
    // known tag.
    mtd addElement(parent: u32, name: HtmlRange, tag: HtmlTag, sourceOffset: u64)->u32
    {
        var node: HtmlNode
        node.kind         = .Element
        node.tag          = tag
        node.parent       = parent
        node.sourceOffset = sourceOffset
        node.attributes   = {cast(u32) .attributePool.count, 0}
        node.classes      = {cast(u32) .classPool.count, 0}
        node.text         = name

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .linkChild(parent, index)
        return index
    }

    // Appends text under `parent`, joining the text node already ending it when there is one.
    //
    // A source read in pieces then produces the same tree as the whole source: two adjacent runs
    // of character data are one text node, which is what the parsing model says they are.
    mtd appendText(parent: u32, text: HtmlRange, sourceOffset: u64)
    {
        let last = .nodes[parent].lastChild
        if last != HtmlNoNode and .nodes[last].kind == .Text
        {
            .joinText(last, text)
            return
        }

        .addText(parent, text, sourceOffset)
    }

    // Extends a text node with a run that follows it in the pool.
    //
    // The two runs are adjacent whenever the previous one is the last thing interned, which is
    // what a source split across chunk boundaries produces; anything else is copied to the end.
    mtd joinText(node: u32, text: HtmlRange)
    {
        let existing = .nodes[node].text
        if existing.start + existing.count == text.start and ((existing.start ^ text.start) & HtmlBuiltText) == 0
        {
            .nodes[node].text.count += text.count
            return
        }

        // Copied out first: appending to the pool can move the bytes both runs point at.
        var joined = String.from(.text(existing))
        joined            += .text(text)
        .nodes[node].text = .intern(joined.toString())
    }

    // Appends a text node under `parent`.
    mtd addText(parent: u32, text: HtmlRange, sourceOffset: u64)
    {
        var node: HtmlNode
        node.kind         = .Text
        node.text         = text
        node.parent       = parent
        node.sourceOffset = sourceOffset

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .linkChild(parent, index)
    }

    // Reports whether the node just before `sibling` under its parent is a text node.
    mtd const precededByText(sibling: u32)->bool
    {
        let previous = .nodes[sibling].prevSibling
        return previous != HtmlNoNode and .nodes[previous].kind == .Text
    }

    // Inserts an element under `sibling`'s parent, placed just before it, and returns its index.
    //
    // This is the foster-parenting insertion the table recovery relies on. Node indices stop
    // following document order here, which nothing reads: the children arrays carry the order.
    mtd insertElementBefore(sibling: u32, name: HtmlRange, tag: HtmlTag, sourceOffset: u64)->u32
    {
        let parent = .nodes[sibling].parent
        var node: HtmlNode
        node.kind         = .Element
        node.tag          = tag
        node.parent       = parent
        node.sourceOffset = sourceOffset
        node.attributes   = {cast(u32) .attributePool.count, 0}
        node.classes      = {cast(u32) .classPool.count, 0}
        node.text         = name

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .linkBefore(sibling, index)
        return index
    }

    // Inserts text just before `sibling`, joining the text node already sitting there when one
    // does, so a fostered run fed in several pieces stays one node.
    mtd insertTextBefore(sibling: u32, text: HtmlRange, sourceOffset: u64)
    {
        let previous = .nodes[sibling].prevSibling
        if previous != HtmlNoNode and .nodes[previous].kind == .Text
        {
            .joinText(previous, text)
            return
        }

        var node: HtmlNode
        node.kind         = .Text
        node.text         = text
        node.parent       = .nodes[sibling].parent
        node.sourceOffset = sourceOffset

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .linkBefore(sibling, index)
    }

    // Records one attribute on an element, keeping the classes in their indexed form.
    //
    // An element's attributes are read in one run, so they extend the pool where the element's own
    // range already ends; nothing else may take an attribute in between.
    mtd addAttribute(element: u32, name: HtmlRange, value: HtmlRange)
    {
        let node = &.nodes[element]
        Debug.assert(node.attributes.start + node.attributes.count == cast(u32) .attributePool.count, "an element's attributes must stay contiguous")

        // The length rejects every other attribute before a byte of it is read.
        if name.count == @countof("class") and .text(name) == "class"
        {
            Debug.assert(node.classes.start + node.classes.count == cast(u32) .classPool.count, "an element's classes must stay contiguous")

            // A class is a run inside the value that is already interned, so the index costs no
            // text of its own.
            let text  = .text(value)
            var start = 0'u64
            while start < @countof(text)
            {
                while start < @countof(text) and Latin1.isSpace(text[start]) do
                    start += 1
                var end = start
                while end < @countof(text) and !Latin1.isSpace(text[end]) do
                    end += 1
                if end == start do
                    break

                .classPool.add({value.start + cast(u32) start, cast(u32) (end - start)})
                .nodes[element].classes.count += 1
                start = end
            }
        }

        var attribute: HtmlAttribute
        attribute.name  = name
        attribute.value = value
        .attributePool.add(attribute)
        .nodes[element].attributes.count += 1
    }

    // Returns an element's name: the spelling of its tag, or the raw name a document used for a
    // tag this engine does not know.
    mtd const name(element: u32)->string
    {
        let node = &.nodes[element]
        if node.kind != .Element do
            return ""
        return node.tag == .Unknown ? .text(node.text) : HtmlDocument.tagName(node.tag)
    }

    // Returns an element's `id`, or an empty string when it carries none.
    mtd const id(element: u32)->string => .attribute(element, "id")

    // Returns the attributes an element carries, in source order.
    mtd const attributes(element: u32)->const [..] HtmlAttribute
    {
        let range = .nodes[element].attributes
        return .attributePool.toSlice()[range.start until range.start + range.count]
    }

    // Returns the classes an element carries, in source order.
    mtd const classes(element: u32)->const [..] HtmlRange
    {
        let range = .nodes[element].classes
        return .classPool.toSlice()[range.start until range.start + range.count]
    }

    // Returns an attribute value, or an empty string when the element does not carry it.
    mtd const attribute(element: u32, name: string)->string
    {
        for attribute in .attributes(element) where .text(attribute.name) == name do
            return .text(attribute.value)
        return ""
    }

    // Reports whether an element carries an attribute, whatever its value.
    mtd const hasAttribute(element: u32, name: string)->bool
    {
        for attribute in .attributes(element) where .text(attribute.name) == name do
            return true
        return false
    }

    // Reports whether an element carries a class.
    mtd const hasClass(element: u32, name: string)->bool
    {
        for value in .classes(element) where .text(value[]) == name do
            return true
        return false
    }

    // Returns the index of `child` among its parent's element children, and how many there are.
    //
    // Structural pseudo-classes count elements, so text nodes never take a position.
    mtd const elementPosition(child: u32)->{ index: u32, count: u32 }
    {
        var result: retval
        let parent = .nodes[child].parent
        if parent == HtmlNoNode do
            return {1, 1}
        for value in .children(parent) where .nodes[value].kind == .Element
        {
            result.count += 1
            if value == child do
                result.index = result.count
        }

        return result
    }

    // Collects the text a subtree contributes, with no regard for how it is laid out.
    //
    // This is what a search runs against, so a skipped element contributes nothing.
    mtd const textContent(root: u32)->String
    {
        var result: retval
        .appendTextContent(&result, root)
        return result
    }

    mtd const appendTextContent(output: *String, index: u32)
    {
        let node = &.nodes[index]
        if node.kind == .Text
        {
            output[] += .text(node.text)
            return
        }

        if node.kind == .Element and HtmlDocument.isSkippedTag(node.tag) do
            return
        if node.tag == .Style do
            return
        for child in .children(index) do
            .appendTextContent(output, child)
    }
}
