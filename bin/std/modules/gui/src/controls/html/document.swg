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
#[Swag.NoDoc]
public struct HtmlRange
{
    start: u32
    count: u32
}

// One node of the parsed tree.
//
// Children are stored as indices into the owning document so the array can grow without
// invalidating anything a caller holds.
//
// A node is deliberately narrow, because a large page holds hundreds of thousands of them and
// the cost of parsing one is dominated by the memory it touches. What only some nodes need lives
// beside the tree: attributes and classes are runs inside the document's pools, an element's name
// comes from its tag, and `text` carries the content of a text node or the raw name of an element
// whose tag this engine does not know.
#[Swag.NoDoc]
public struct HtmlNode
{
    kind:         HtmlNodeKind
    tag:          HtmlTag
    text:         HtmlRange
    children:     Array'u32
    parent = HtmlNoNode
    sourceOffset: u64
    attributes:   HtmlRange
    classes:      HtmlRange
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
    textPool:      String
}

impl HtmlDocument
{
    // Resolves an element name to its interned tag.
    func tagFromName(name: string)->HtmlTag
    {
        switch name
        {
        case "a":          return .A
        case "abbr":       return .Abbr
        case "address":    return .Address
        case "area":       return .Area
        case "article":    return .Article
        case "aside":      return .Aside
        case "b":          return .B
        case "base":       return .Base
        case "blockquote": return .Blockquote
        case "body":       return .Body
        case "br":         return .Br
        case "button":     return .Button
        case "canvas":     return .Canvas
        case "caption":    return .Caption
        case "cite":       return .Cite
        case "code":       return .Code
        case "col":        return .Col
        case "colgroup":   return .ColGroup
        case "dd":         return .Dd
        case "del":        return .Del
        case "details":    return .Details
        case "dfn":        return .Dfn
        case "div":        return .Div
        case "dl":         return .Dl
        case "dt":         return .Dt
        case "em":         return .Em
        case "embed":      return .Embed
        case "fieldset":   return .FieldSet
        case "figcaption": return .FigCaption
        case "figure":     return .Figure
        case "footer":     return .Footer
        case "form":       return .Form
        case "h1":         return .H1
        case "h2":         return .H2
        case "h3":         return .H3
        case "h4":         return .H4
        case "h5":         return .H5
        case "h6":         return .H6
        case "head":       return .Head
        case "header":     return .Header
        case "hgroup":     return .HGroup
        case "hr":         return .Hr
        case "html":       return .Html
        case "i":          return .I
        case "iframe":     return .IFrame
        case "img":        return .Img
        case "input":      return .Input
        case "ins":        return .Ins
        case "kbd":        return .Kbd
        case "label":      return .Label
        case "legend":     return .Legend
        case "li":         return .Li
        case "link":       return .Link
        case "main":       return .Main
        case "mark":       return .Mark
        case "menu":       return .Menu
        case "meta":       return .Meta
        case "nav":        return .Nav
        case "noscript":   return .NoScript
        case "object":     return .Object
        case "ol":         return .Ol
        case "optgroup":   return .OptGroup
        case "option":     return .Option
        case "output":     return .Output
        case "p":          return .P
        case "param":      return .Param
        case "picture":    return .Picture
        case "pre":        return .Pre
        case "progress":   return .Progress
        case "q":          return .Q
        case "rp":         return .Rp
        case "rt":         return .Rt
        case "ruby":       return .Ruby
        case "s":          return .S
        case "samp":       return .Samp
        case "script":     return .Script
        case "section":    return .Section
        case "select":     return .Select
        case "small":      return .Small
        case "source":     return .Source
        case "span":       return .Span
        case "strong":     return .Strong
        case "style":      return .Style
        case "sub":        return .Sub
        case "summary":    return .Summary
        case "sup":        return .Sup
        case "svg":        return .Svg
        case "table":      return .Table
        case "tbody":      return .TBody
        case "td":         return .Td
        case "template":   return .Template
        case "textarea":   return .TextArea
        case "tfoot":      return .TFoot
        case "th":         return .Th
        case "thead":      return .THead
        case "time":       return .Time
        case "title":      return .Title
        case "tr":         return .Tr
        case "track":      return .Track
        case "u":          return .U
        case "ul":         return .Ul
        case "var":        return .Var
        case "video":      return .Video
        case "wbr":        return .Wbr
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
        .textPool.clear()
        var root: HtmlNode
        root.kind = .Document
        .nodes.add(#move root)
    }

    // Copies a run of source text into the pool and returns where it landed.
    //
    // A run is addressed by offset, so every slice the document hands out is invalidated by the
    // next call: read one back with [[HtmlDocument.text]] where it is used, and never keep it
    // across a parser feed.
    mtd intern(text: string)->HtmlRange
    {
        var result: retval
        result.start = cast(u32) .textPool.length
        result.count = cast(u32) @countof(text)
        .textPool    += text
        return result
    }

    // Copies a run and folds it to lower case in place, which is what tag and attribute names
    // are stored as.
    mtd internLower(text: string)->HtmlRange
    {
        let result = .intern(text)
        let buffer = .textPool.buffer!
        for index in result.count do
            buffer[result.start + index] = Latin1.toLower(buffer[result.start + index])
        return result
    }

    // Copies a run of source text into the pool, resolving the character references it carries.
    mtd internDecoded(text: string, inAttribute = false)->HtmlRange
    {
        var result: retval
        result.start = cast(u32) .textPool.length
        htmlDecodeInto(&.textPool, text, inAttribute)
        result.count = cast(u32) .textPool.length - result.start
        return result
    }

    // Returns the text a run holds.
    mtd const text(range: HtmlRange)->string => .textPool.toString()[range.start until range.start + range.count]

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

        let text = Math.min(bytes / 2, MaxReservedText)
        if text > .textPool.capacity do
            .textPool.reserve(text)
    }

    mtd node(index: u32)->*HtmlNode => &.nodes[index]

    mtd const constNode(index: u32)->const *HtmlNode => &.nodes[index]

    // Appends an element under `parent` and returns its index.
    //
    // The caller hands over the folded name and the tag it already resolved from it: the parser
    // needs that tag before the node exists, and resolving a name is a string comparison per
    // known tag.
    mtd addElement(parent: u32, name: string, tag: HtmlTag, sourceOffset: u64)->u32
    {
        // Only a tag this engine does not know has to remember how it was spelled.
        var interned: HtmlRange
        if tag == .Unknown do
            interned = .intern(name)

        var node: HtmlNode
        node.kind         = .Element
        node.tag          = tag
        node.parent       = parent
        node.sourceOffset = sourceOffset
        node.attributes   = {cast(u32) .attributePool.count, 0}
        node.classes      = {cast(u32) .classPool.count, 0}
        node.text         = interned

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .nodes[parent].children.add(index)
        return index
    }

    // Appends text under `parent`, joining the text node already ending it when there is one.
    //
    // A source read in pieces then produces the same tree as the whole source: two adjacent runs
    // of character data are one text node, which is what the parsing model says they are.
    mtd appendText(parent: u32, text: HtmlRange, sourceOffset: u64)
    {
        let children = &.nodes[parent].children
        if children.count
        {
            let last = children.back()
            if .nodes[last].kind == .Text
            {
                .joinText(last, text)
                return
            }
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
        if existing.start + existing.count == text.start
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
        .nodes[parent].children.add(index)
    }

    // Returns the position of `child` in `parent`'s children array.
    mtd const childPosition(parent, child: u32)->u64
    {
        var position = 0'u64
        while position < .nodes[parent].children.count and .nodes[parent].children[position] != child do
            position += 1
        return position
    }

    // Reports whether the node just before `sibling` under its parent is a text node.
    mtd const precededByText(sibling: u32)->bool
    {
        let parent = .nodes[sibling].parent
        if parent == HtmlNoNode do
            return false

        let position = .childPosition(parent, sibling)
        if !position do
            return false
        return .nodes[.nodes[parent].children[position - 1]].kind == .Text
    }

    // Inserts an element under `sibling`'s parent, placed just before it, and returns its index.
    //
    // This is the foster-parenting insertion the table recovery relies on. Node indices stop
    // following document order here, which nothing reads: the children arrays carry the order.
    mtd insertElementBefore(sibling: u32, name: string, tag: HtmlTag, sourceOffset: u64)->u32
    {
        var interned: HtmlRange
        if tag == .Unknown do
            interned = .intern(name)

        let parent = .nodes[sibling].parent
        var node: HtmlNode
        node.kind         = .Element
        node.tag          = tag
        node.parent       = parent
        node.sourceOffset = sourceOffset
        node.attributes   = {cast(u32) .attributePool.count, 0}
        node.classes      = {cast(u32) .classPool.count, 0}
        node.text         = interned

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .nodes[parent].children.insertAt(.childPosition(parent, sibling), index)
        return index
    }

    // Inserts text just before `sibling`, joining the text node already sitting there when one
    // does, so a fostered run fed in several pieces stays one node.
    mtd insertTextBefore(sibling: u32, text: HtmlRange, sourceOffset: u64)
    {
        let parent   = .nodes[sibling].parent
        let position = .childPosition(parent, sibling)
        if position
        {
            let previous = .nodes[parent].children[position - 1]
            if .nodes[previous].kind == .Text
            {
                .joinText(previous, text)
                return
            }
        }

        var node: HtmlNode
        node.kind         = .Text
        node.text         = text
        node.parent       = parent
        node.sourceOffset = sourceOffset

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .nodes[parent].children.insertAt(position, index)
    }

    // Records one attribute on an element, keeping the classes in their indexed form.
    //
    // An element's attributes are read in one run, so they extend the pool where the element's own
    // range already ends; nothing else may take an attribute in between.
    mtd addAttribute(element: u32, name: HtmlRange, value: HtmlRange)
    {
        let node = &.nodes[element]
        Debug.assert(node.attributes.start + node.attributes.count == cast(u32) .attributePool.count, "an element's attributes must stay contiguous")

        if .text(name) == "class"
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
        for value in .nodes[parent].children where .nodes[value].kind == .Element
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
        for child in node.children do
            .appendTextContent(output, child)
    }
}
