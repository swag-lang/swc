#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    let source = "<style>body{background:#101820;color:#f0f0f0;max-width:760px}h1{font-size:34px;color:#f7f900}.lead{font-size:19px;text-align:center}</style><main><h1>Styled page</h1><p class=\"lead\">CSS is applied.</p><blockquote>Readable quote</blockquote><pre>let value = 42</pre></main>"
    let rules  = parseHtmlCss(source)
    let body   = htmlBodyCssStyle(source, rules.toSlice())
    let blocks = parseHtmlBlocks(source, rules.toSlice())
    @assert(rules.count == 3)
    @assert(body.background.a == 255 and body.maxWidth == 760)
    @assert(blocks.count == 4)
    @assert(blocks[0].kind == .Heading1 and blocks[0].style.fontSize == 34)
    @assert(blocks[1].style.fontSize == 19 and blocks[1].style.align == .Center)
    @assert(blocks[2].kind == .Quote)
    @assert(blocks[3].kind == .Code)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = HtmlPluginView.createLoaded(&host.root, "<style>body{max-width:820px}h1{font-size:32px}.note{color:tomato}</style><article><h1>HTML document</h1><p class=\"note\">Styles remain part of the document.</p><table><tr><th>Engine</th><th>Mode</th></tr><tr><td>Native</td><td>Offline</td></tr></table></article>")
    view.resize(960, 680)
    view.applyLayout()
    view.layoutDocument()
    @assert(view.blocks.count == 3)
    @assert(view.page.position.width == 820)
    Testing.assertContentFits(view)

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.html.document")
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_html_stream_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<main>"
    for 2_000 do
        source += "<h2>Streamed heading</h2><p>A paragraph stays on disk until the viewport approaches it.</p>"
    source += "</main>"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = HtmlPluginView.create(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    view.layoutDocument()
    view.streamStep()

    @assert(!view.blocks.isEmpty())
    @assert(view.stream.isOpen())
    @assert(expect view.stream.position() < source.length)
}
