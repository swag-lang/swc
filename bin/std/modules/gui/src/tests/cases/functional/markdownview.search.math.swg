#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A formula is one navigable search result, even when its source repeats the query.
#test
{
    var source = String.from("$$\\alpha + \\alpha$$\n\n")
    for index in 40 do
        source += Format.toString("A filler paragraph % keeps the next formula outside the viewport.\n\n", index)
    source += "$$\\alpha + \\alpha$$"

    var host: Testing.HeadlessHost
    host.setup(640, 240)
    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()

    Swag.require(view.findText("alpha") and view.searchBlockIndex == 0)
    let firstPosition = view.scroll.scrollPosition().y
    Swag.require(view.findText("alpha") and view.searchBlockIndex > 0)
    let secondPosition = view.scroll.scrollPosition().y
    Swag.require(secondPosition > firstPosition)
    Swag.require(view.findText("alpha") and view.searchBlockIndex == 0)
    Swag.require(view.scroll.scrollPosition().y == firstPosition)
}
