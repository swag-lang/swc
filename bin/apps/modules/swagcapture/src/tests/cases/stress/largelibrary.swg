#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Browse, sort and search a library much larger than its visible grid.
#[Swag.TestTag("stress")]
#test
{
    var fixture: HeadlessFixture
    fixture.setup()
    defer fixture.shutdown()
    fixture.main.libWnd = LibraryWnd.create(fixture.main)
    let library = fixture.main.libWnd
    let view    = library.view

    for index in 800
    {
        let name = Format.toString("capture%.scc", index)
        let title = index == 799 ? "Target final capture" : "Regular capture"
        discard testAddLibraryItem(view, name, cast(u64, index + 1),
                                   cast(u16, 1 + index % 28), title: title)
    }
    Swag.require(view.items.count == 800)
    fixture.main.applyLayout()
    var image = fixture.gui.render(library)
    Swag.require(image.isValid())
    var visible = 0
    for item in view.items where item.visible do
        visible += 1
    Swag.require(visible > 0 and visible < 800)

    library.sortMethod = .FileSize
    view.sort()
    Swag.require(view.items[0].fi.size == 800)
    library.setSearch("target final")
    Swag.require(view.items.count == 1 and view.items[0].fi.size == 800)
    image = fixture.gui.render(library)
    Swag.require(image.isValid())

    library.setSearch("")
    Swag.require(view.items.count == 800)
    library.invertSort = true
    view.sort()
    Swag.require(view.items[0].fi.size == 1)
}
