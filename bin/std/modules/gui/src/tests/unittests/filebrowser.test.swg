#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// The file browser composite builds its sub-controls and resolves selections
// independently of any dialog/surface.
//
// We do not point it at a real folder here: listing a folder builds per-file
// icons through the renderer, which is absent in headless mode. The selection
// logic (name + filter extension) is pure and is what we validate.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 460)

    var opt: FileDlgOptions
    opt.mode              = .SelectFile
    opt.showLocationsPane = false
    opt.filters.add({"Text", ".txt"})

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    @assert(@isset(fb.editFile))
    @assert(@isset(fb.comboType))
    @assert(@isset(fb.listCtrl))
    @assert(fb.comboType.items.count == 1)

    // The file list is multi-column with fixed default widths.
    @assert(fb.listCtrl.header.items.count == 2)
    @assert(Math.abs(fb.listCtrl.header.itemWidthAt(0) - 200) < 0.5)
    @assert(Math.abs(fb.listCtrl.header.itemWidthAt(1) - 150) < 0.5)

    // selectedPath combines the folder + typed name and appends the active
    // filter extension when missing.
    fb.setFileName("notes")
    @assert(fb.fileName() == "notes")
    let name     = fb.selectedPath()
    let fileName = notnull Path.fileName(name.toString())
    @assert(fileName == "notes.txt")

    // A name that already carries the extension is kept as-is.
    fb.setFileName("report.txt")
    let name2     = fb.selectedPath()
    let fileName2 = notnull Path.fileName(name2.toString())
    @assert(fileName2 == "report.txt")
    @assert(!fb.setCurrentFolder("this-folder-does-not-exist"))
    @assert(!fb.createFolder("bad/name"))

    host.shutdown()
}

// SelectFolder mode offers a single "Folders" type entry.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 460)

    var opt: FileDlgOptions
    opt.mode              = .SelectFolder
    opt.showLocationsPane = false

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    @assert(fb.comboType.items.count == 1)
    @assert(@isset(fb.editFile))

    // selectedPath must not index the (empty) filter list in SelectFolder mode.
    fb.setFileName("myfolder")
    let name     = fb.selectedPath()
    let fileName = notnull Path.fileName(name.toString())
    @assert(fileName == "myfolder")

    host.shutdown()
}
