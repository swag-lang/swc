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
#[Swag.NoDoc]
public struct HtmlAttribute
{
    name:  String
    value: String
}

// One node of the parsed tree.
//
// Children are stored as indices into the owning document so the array can grow without
// invalidating anything a caller holds.
#[Swag.NoDoc]
public struct HtmlNode
{
    kind:         HtmlNodeKind
    tag:          HtmlTag
    name:         String
    text:         String
    attributes:   Array'HtmlAttribute
    children:     Array'u32
    parent = HtmlNoNode
    sourceOffset: u64
    id:           String
    classes:      Array'String
}

// A parsed HTML tree.
//
// Node 0 is always the document node and never has a parent. The tree keeps the source offset of
// every node so a viewer can map a byte position in the file back to what is drawn for it.
#[Swag.NoDoc]
public struct HtmlDocument
{
    nodes: Array'HtmlNode
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
        var root: HtmlNode
        root.kind = .Document
        .nodes.add(#move root)
    }

    mtd node(index: u32)->*HtmlNode => &.nodes[index]

    mtd const constNode(index: u32)->const *HtmlNode => &.nodes[index]

    // Appends an element under `parent` and returns its index.
    mtd addElement(parent: u32, name: string, sourceOffset: u64)->u32
    {
        var node: HtmlNode
        node.kind         = .Element
        node.name         = name
        node.tag          = HtmlDocument.tagFromName(name)
        node.parent       = parent
        node.sourceOffset = sourceOffset

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .nodes[parent].children.add(index)
        return index
    }

    // Appends text under `parent`, joining the text node already ending it when there is one.
    //
    // A source read in pieces then produces the same tree as the whole source: two adjacent runs
    // of character data are one text node, which is what the parsing model says they are.
    mtd appendText(parent: u32, text: string, sourceOffset: u64)
    {
        let children = &.nodes[parent].children
        if children.count
        {
            let last = children.back()
            if .nodes[last].kind == .Text
            {
                .nodes[last].text += text
                return
            }
        }

        .addText(parent, text, sourceOffset)
    }

    // Appends a text node under `parent`.
    mtd addText(parent: u32, text: string, sourceOffset: u64)
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
    mtd insertElementBefore(sibling: u32, name: string, sourceOffset: u64)->u32
    {
        let parent = .nodes[sibling].parent
        var node: HtmlNode
        node.kind         = .Element
        node.name         = name
        node.tag          = HtmlDocument.tagFromName(name)
        node.parent       = parent
        node.sourceOffset = sourceOffset

        let index = cast(u32) .nodes.count
        .nodes.add(#move node)
        .nodes[parent].children.insertAt(.childPosition(parent, sibling), index)
        return index
    }

    // Inserts text just before `sibling`, joining the text node already sitting there when one
    // does, so a fostered run fed in several pieces stays one node.
    mtd insertTextBefore(sibling: u32, text: string, sourceOffset: u64)
    {
        let parent   = .nodes[sibling].parent
        let position = .childPosition(parent, sibling)
        if position
        {
            let previous = .nodes[parent].children[position - 1]
            if .nodes[previous].kind == .Text
            {
                .nodes[previous].text += text
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

    // Records one attribute on an element, keeping `id` and `class` in their indexed form.
    mtd addAttribute(element: u32, name: string, value: string)
    {
        let node = &.nodes[element]
        switch name
        {
        case "id":
            node.id = value

        case "class":
            for part in Tokenize.split(value, ' 'u8) where @countof(part) do
                node.classes.add(String.from(part))
        }

        var attribute: HtmlAttribute
        attribute.name  = name
        attribute.value = value
        node.attributes.add(#move attribute)
    }

    // Returns an attribute value, or an empty string when the element does not carry it.
    mtd const attribute(element: u32, name: string)->string
    {
        for attribute in .nodes[element].attributes where attribute.name == name do
            return attribute.value.toString()
        return ""
    }

    // Reports whether an element carries an attribute, whatever its value.
    mtd const hasAttribute(element: u32, name: string)->bool
    {
        for attribute in .nodes[element].attributes where attribute.name == name do
            return true
        return false
    }

    // Reports whether an element carries a class.
    mtd const hasClass(element: u32, name: string)->bool
    {
        for value in .nodes[element].classes where value.toString() == name do
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
            output[] += node.text
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
