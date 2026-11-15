#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Whitespace scanning never splits a UTF-8 codepoint or turns a no-break space into a break.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    let source = "<style>p { width: 60px; margin: 0; font-size: 24px }</style><p id='title'>STAVE&nbsp;III</p><p id='accent'>voilà</p>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(400, 300)
    view.applyLayout()
    for id, index in ["title", "accent"]
    {
        let box       = view.layout.constBox(view.boxOfNode(view.elementById(id)))
        var textItems = 0'u32
        for item in box.items where item.kind == .Text
        {
            let text = view.layout.inlineText(item)
            Swag.require(Utf8.isValid(cast(const [..] u8, text)))
            Swag.require(text == (index == 0 ? "STAVE III" : "voilà"))
            textItems += 1
        }

        Swag.require(textItems == 1 and box.lines.count == 1)
    }
}

// ASCII form feed is a segment break; its preserved form must advance rather than stall.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    let source = "<p id='normal'>first\x0Csecond</p><pre id='pre'>first\x0Csecond</pre>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(400, 300)
    view.applyLayout()
    let normal = view.layout.constBox(view.boxOfNode(view.elementById("normal")))
    let pre    = view.layout.constBox(view.boxOfNode(view.elementById("pre")))
    Swag.require(normal.lines.count == 1 and pre.lines.count == 2)
}
