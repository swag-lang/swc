#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core, File

// The file browser composite builds its sub-controls and resolves selections
// independently of any dialog/surface.
//
// We do not point it at a real folder here: listing a folder builds per-file
// icons through the renderer, which is absent in headless mode. The selection
// logic (name + filter extension) is pure and is what we validate.
#test
{
    var host: GuiHeadlessHost
    host.setup(640, 460)

    var opt: FileDlgOptions
    opt.mode      = .SelectOneFile
    opt.drivePane = false
    opt.filters.add({"Text", ".txt"})

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    @assert(fb.editFile != null)
    @assert(fb.comboType != null)
    @assert(fb.listCtrl != null)
    @assert(fb.comboType.items.count == 1)

    // The file list is multi-column with fixed default widths.
    @assert(fb.listCtrl.header.items.count == 2)
    @assert(Math.abs(fb.listCtrl.header.getItemWidth(0) - 200) < 0.5)
    @assert(Math.abs(fb.listCtrl.header.getItemWidth(1) - 150) < 0.5)

    // getSelectedName combines the folder + typed name and appends the active
    // filter extension when missing.
    fb.editFile.setText("notes")
    let name     = fb.getSelectedName()
    let fileName = assume Path.getFileName(name.toString())
    @assert(fileName == "notes.txt")

    // A name that already carries the extension is kept as-is.
    fb.editFile.setText("report.txt")
    let name2     = fb.getSelectedName()
    let fileName2 = assume Path.getFileName(name2.toString())
    @assert(fileName2 == "report.txt")

    host.shutdown()
}

// SelectFolder mode offers a single "Folders" type entry.
#test
{
    var host: GuiHeadlessHost
    host.setup(640, 460)

    var opt: FileDlgOptions
    opt.mode      = .SelectFolder
    opt.drivePane = false

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    @assert(fb.comboType.items.count == 1)
    @assert(fb.editFile != null)

    // getSelectedName must not index the (empty) filter list in SelectFolder mode.
    fb.editFile.setText("myfolder")
    let name     = fb.getSelectedName()
    let fileName = assume Path.getFileName(name.toString())
    @assert(fileName == "myfolder")

    host.shutdown()
}
