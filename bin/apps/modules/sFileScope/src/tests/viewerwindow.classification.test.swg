#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func assertClassificationFolder(result: const *ViewerClassifiedFile, names: const [..] String)
{
    @assert(result.folderFiles.count == @countof(names))
    for name, index in names do
        @assert(result.folderFiles[index] == name[])
}

// Reusing the asynchronous classifier replaces its previous folder snapshot. It must never append
// a second scan when the reader selects another file from the same folder.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_classification_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var host: Testing.HeadlessHost
    host.setup(64, 64)
    defer host.shutdown()

    var names: Array'String
    for i in 3'u32
    {
        let fileName = Path.combine(folder.toString(), Format.toString("file%.txt", i).toString())
        discard expect File.writeAllBytes(fileName.toString(), cast(const [..] u8) "a readable line\n")
        names.add(fileName)
    }

    var index = createViewerPluginRegistry()
    var load:   ViewerChoiceLoad
    var recent: Array'String

    load.start(&index, names[0].toString(), recent.toSlice())
    Jobs.wait(&load.job)
    var first = load.finish()
    assertClassificationFolder(&first, names.toSlice())

    load.start(&index, names[2].toString(), recent.toSlice())
    Jobs.wait(&load.job)
    var second = load.finish()
    assertClassificationFolder(&second, names.toSlice())
}
