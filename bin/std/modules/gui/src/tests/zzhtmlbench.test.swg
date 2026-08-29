#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Temporary probe: what the HTML parser costs per megabyte of real source.

// The A/B protocol needs a short run: this laptop's clocks fall over a sustained load, so a probe
// that runs for seven seconds measures its own thermal ramp. The full breakdown is opt-in.
const BenchFull = false

func benchFixture(name: string)->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, Format.toString("datas/%", name).toString())
}

func mix(hash: u64, value: u64)->u64
{
    var result = hash ^ value
    result *= 0x100000001b3
    return result
}

func mixText(hash: u64, text: string)->u64
{
    var result = mix(hash, @countof(text))
    for index in @countof(text) do
        result = mix(result, cast(u64) text[index])
    return result
}

// Digests every decision the parser made, so a change to its speed proves it changed nothing else.
func treeDigest(document: const *HtmlDocument)->u64
{
    var hash = 0xcbf29ce484222325'u64
    for index in document.nodes.count
    {
        let node = document.constNode(cast(u32) index)
        hash = mix(hash, cast(u64) node.kind)
        hash = mix(hash, cast(u64) node.tag)
        hash = mix(hash, node.sourceOffset)
        hash = mix(hash, cast(u64) node.parent)
        hash = mixText(hash, document.textOf(cast(u32) index))
        for child in document.children(cast(u32) index) do
            hash = mix(hash, cast(u64) child)
        if node.kind != .Element do
            continue

        hash = mixText(hash, document.name(cast(u32) index))
        hash = mixText(hash, document.id(cast(u32) index))
        for klass in document.classes(cast(u32) index) do
            hash = mixText(hash, document.text(klass[]))
        for attribute in document.attributes(cast(u32) index)
        {
            hash = mixText(hash, document.text(attribute.name))
            hash = mixText(hash, document.text(attribute.value))
        }
    }

    return hash
}


// The same lookup written as one flat table, to price what a `switch` over strings costs.
func tagFromNameFlat(name: string)->HtmlTag
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

    return HtmlTag.Unknown
}

// What resolving an element name costs, on the names the corpus actually holds.
func benchSwitch(name: string)
{
    let source   = expect File.readAllText(benchFixture(name))
    var document = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&document)
    parser.feed(source.toString())
    parser.finish()

    var names: Array'String
    for index in document.nodes.count where document.constNode(cast(u32) index).kind == .Element do
        names.add(String.from(document.name(cast(u32) index)))

    // The worst case of the table: a name of every length that matches nothing, so every case is
    // tested. This is what an unknown element costs, and what prices one comparison.
    var misses: Array'String
    for length in 1 to 12
    {
        var text: String
        for length do
            text += "z"
        misses.add(text)
    }

    var sink = 0'u64
    for round in 3
    {
        var watch: Time.Stopwatch
        watch.restart()
        for repeat in 12_000
        {
            for value in misses do
                sink += cast(u64) tagFromNameFlat(value.toString())
        }

        watch.stop()
        let calls = 12_000 * misses.count
        Console.printf("[miss] calls=% flat=%us flatNs=%\n", calls, watch.elapsedMicroseconds(), (watch.elapsedMicroseconds() * 1000) / calls)
    }

    for round in 3
    {
        var watch: Time.Stopwatch
        watch.restart()
        for value in names do
            sink += cast(u64) HtmlDocument.tagFromName(value.toString())
        watch.stop()
        let bucketed = watch.elapsedMicroseconds()

        watch.restart()
        for value in names do
            sink += cast(u64) tagFromNameFlat(value.toString())
        watch.stop()

        Console.printf("[switch] names=% bucketed=%us flat=%us bucketedNs=% flatNs=%\n", names.count, bucketed, watch.elapsedMicroseconds(), (bucketed * 1000) / names.count, (watch.elapsedMicroseconds() * 1000) / names.count)
    }

    Console.printf("[switch] sink=%\n", sink)
}

func benchOne(name: string, passes: u64, chunked: bool, reserve = 0'u64)
{
    let source = expect File.readAllText(benchFixture(name))
    let text   = source.toString()

    var best   = Swag.U64.Max
    var total  = 0'u64
    var nodes  = 0'u64
    var digest = 0'u64

    for pass in passes
    {
        var document = HtmlDocument.create()
        if reserve do
            document.reserveForSource(reserve)
        var parser: HtmlParser
        parser.start(&document)

        var watch: Time.Stopwatch
        watch.start()
        if chunked
        {
            var offset = 0'u64
            while offset < @countof(text)
            {
                let end = Math.min(offset + 48 * 1024, @countof(text))
                parser.feed(text[offset until end])
                offset = end
            }
        }
        else
        {
            parser.feed(text)
        }

        parser.finish()
        watch.stop()

        let micro = watch.elapsedMicroseconds()
        best   = Math.min(best, micro)
        total += micro
        nodes  = document.nodes.count
        if !pass do
            digest = treeDigest(&document)
    }

    let mbPerSec = (@countof(text) * 1_000_000) / (best * 1024 * 1024)
    Console.printf("[bench] % % reserve=% bytes=% nodes=% best=%us mean=%us %MB/s digest=%\n", name, chunked ? "chunked" : "whole", reserve, @countof(text), nodes, best, total / passes, mbPerSec, digest)
}

// What the parsed tree costs in live allocator blocks, which is what a per-node String or Array
// turns into.
func benchAllocations(name: string)
{
    let source    = expect File.readAllText(benchFixture(name))
    let allocator = Swag.defaultAllocator()

    let before = allocator.stats()

    var document = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&document)
    parser.feed(source.toString())
    parser.finish()

    let after    = allocator.stats()
    let blocks   = after.countAlloc - before.countAlloc
    let bytes    = after.sizeAlloc - before.sizeAlloc
    var elements = 0'u64
    for index in document.nodes.count where document.constNode(cast(u32) index).kind == .Element do
        elements += 1

    Console.printf("[alloc] % nodes=% elements=% blocks=% bytes=%\n", name, document.nodes.count, elements, blocks, bytes)
}

#test
{
    Console.printf("[size] HtmlNode=% HtmlAttribute=% String=% Array=%\n", #sizeof(HtmlNode), #sizeof(HtmlAttribute), #sizeof(String), #sizeof(Array'u32))

    var repro: String = "<style>"
    repro += ":root { --ink: #102030 }"
    repro += "p { color: #ff0000 }"
    repro += "</style>"
    repro += "<p class=\"note\" id=\"one\">text</p><div><em>inner</em></div>"

    var document = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&document)
    parser.feed(repro.toString())
    parser.finish()

    for index in document.nodes.count
    {
        let node   = document.constNode(cast(u32) index)
        var walked = 0'u64
        var child  = node.firstChild
        while child != HtmlNoNode and walked <= document.nodes.count
        {
            walked += 1
            child   = document.constNode(child).nextSibling
        }

        Console.printf("[chain] node=% kind=% tag=% parent=% first=% last=% next=% prev=% walked=%\n", index, node.kind, node.tag, node.parent, node.firstChild, node.lastChild, node.nextSibling, node.prevSibling, walked)
    }

    benchSwitch("html.rustdoc-large.html")
    benchOne("html.rustdoc-large.html", 3, false)

    if BenchFull
    {
        benchOne("html.rustdoc-large.html", 3, true)
        benchAllocations("html.rustdoc-large.html")
    }
}
