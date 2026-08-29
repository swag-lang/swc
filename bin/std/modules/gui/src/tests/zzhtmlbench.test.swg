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

    benchOne("html.rustdoc-large.html", 3, false)

    if BenchFull
    {
        benchOne("html.rustdoc-large.html", 3, true)
        benchAllocations("html.rustdoc-large.html")
    }
}
