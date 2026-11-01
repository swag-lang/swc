#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

#[Swag.TestTag("golden")]
#test
{
    // The page takes the file's name as its title: the photographed file has a name of its own.
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-table-%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let fileName = Path.combine(folder, "projects.tsv")
    expect File.writeAllBytes(fileName, "Name\tLanguage\tFiles\tStatus\nCore\tSwag\t148\tReady\nGui\tSwag\t203\tReady\nSwag Scope\tSwag\t61\tActive\n")

    var host: Testing.HeadlessHost
    host.setup(900, 560)

    var result = openTestViewer(Table.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null)
    let view = assume cast(*Table.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle = .Center

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    assertScopeImageGolden(&image, "viewer.table.document")
}
