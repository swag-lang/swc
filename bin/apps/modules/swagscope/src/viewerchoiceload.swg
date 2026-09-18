using Core

// Everything the worker learns about one requested file, handed to the window in one move.
struct ViewerClassifiedFile
{
    absoluteFileName: String
    fileSize:         String
    choices:          Array'ViewerPluginChoice
    folderFiles:      Array'String
    recent:           Array'String
    exists:           bool
    metadata:         File.FileInfo
}

// Classifies one requested file without making the GUI thread open or probe it.
struct ViewerChoiceLoad
{
    using operation: Viewer.BackgroundOperation
    index:           *ViewerPluginRegistry?
    fileName:        String
    recent:          Array'String
    result:          ViewerClassifiedFile
}

impl ViewerChoiceLoad
{
    mtd start(index: *ViewerPluginRegistry, fileName: string, recent: const [..] String)
    {
        Swag.assert(not .started)

        // The operation is reusable. A completed result was moved to the window, so rebuild every
        // owning field before the worker appends the next folder and history snapshot.
        .result   = {}
        .index    = index
        .fileName = fileName
        .recent   = recent
        .started  = true

        let operation = me
        .task.submit(func|operation|()
        {
            var absolute = catch Path.absolute(operation.fileName.toString()) as pathError
            if pathError != null do
                absolute = operation.fileName
            operation.result.absoluteFileName = #move absolute
            operation.result.exists = File.exists(operation.result.absoluteFileName.toString())
            if operation.result.exists
            {
                operation.result.choices = operation.index!.choices(operation.result.absoluteFileName.toString())
                let info = catch File.info(operation.result.absoluteFileName.toString()) as infoError
                if infoError == null
                {
                    operation.result.fileSize = StrConv.toDisplaySize(info.size)
                    operation.result.metadata = #move info
                }
            }

            for one in operation.recent where File.exists(one[].toString()) do
                operation.result.recent.add(one[])

            let folder = Path.directoryName(operation.result.absoluteFileName.toString())
            if not folder do
                return
            let files = catch Directory.enumerateFiles(folder) as listError
            if listError != null do
                return
            for file in files where not file.isDirectory() do
                operation.result.folderFiles.add(file.fullName)

            operation.result.folderFiles.sort(func(a, b) => Utf8.compare(a.toSlice(), b.toSlice(), .Latin1NoCase))
        })
    }

    // Hands the classification to the caller once the worker is done with it.
    mtd finish()->ViewerClassifiedFile
    {
        Swag.assert(.isDone())
        .wait()
        return #move .result
    }

    mtd opDrop()
    {
        .wait()
    }
}
