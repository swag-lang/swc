#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Search navigation counts rendered link labels, not occurrences hidden in link destinations.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)

    let source = String.from("[alpha](https://example.test/alpha)\n\nalpha")
    let view   = Markdown.View.createText(&host.root, source.toString())
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()

    Swag.require(view.findText("alpha"))
    var first: Math.Rectangle
    Swag.require(view.searchMatchRect(&first))

    let secondOffset = source.length - 5
    Swag.require(view.revealTextMatch(source.toString(), secondOffset, "alpha"))
    var second: Math.Rectangle
    Swag.require(view.searchMatchRect(&second) and second.y > first.y)
}
