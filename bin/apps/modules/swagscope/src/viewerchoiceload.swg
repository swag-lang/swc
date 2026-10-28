using Core

// Everything the worker learns about one requested file, handed to the window in one move.
struct ViewerClassifiedFile
{
    absoluteFileName: String
    fileSize:         String
    choices:          Array'ViewerPluginChoice
    folderFiles:      Array'String
    isDirectory:      bool
    exists:           bool
    metadata:         File.FileInfo
}

// Classifies one requested file without making the GUI thread open or probe it.
struct ViewerChoiceLoad
{
    using operation:  Viewer.BackgroundOperation
    index:            *ViewerPluginRegistry?
    fileName:         String
    result:           ViewerClassifiedFile
    includeNeighbors: bool
}

impl ViewerChoiceLoad
{
    // Classifies `fileName` on the worker task: its absolute path, existence, viewer choices, size
    // and metadata, and the sorted files of its folder. `owner` receives a [[Gui.TaskEvent]] when
    // the classification ends.
    mtd start(index: *ViewerPluginRegistry, fileName: string, owner: *Wnd? = null, includeNeighbors = true)
    {
        Swag.assert(not .started)

        // The operation is reusable. A completed result was moved to the window, so rebuild every
        // owning field before the worker appends the next folder and history snapshot.
        .result           = {}
        .index            = index
        .fileName         = fileName
        .includeNeighbors = includeNeighbors

        let operation = me
        .submit(func|operation|()
        {
            var pathErrorOutcome: Swag.Error
            var absolute:         #decltype(expect Path.absolute(operation.fileName))
            catch { absolute = try Path.absolute(operation.fileName) } as pathErrorOutcome
            let pathError = pathErrorOutcome.value()
            if pathError != null do
                absolute = operation.fileName
            operation.result.absoluteFileName = #move absolute
            operation.result.isDirectory      = Directory.exists(operation.result.absoluteFileName)
            operation.result.exists           = operation.result.isDirectory or File.exists(operation.result.absoluteFileName)
            if operation.result.exists and not operation.result.isDirectory
            {
                operation.result.choices = operation.index!.choices(operation.result.absoluteFileName)
                var infoErrorOutcome: Swag.Error
                var info: #decltype(expect File.info(operation.result.absoluteFileName))
                catch { info = try File.info(operation.result.absoluteFileName) } as infoErrorOutcome
                let infoError = infoErrorOutcome.value()
                if infoError == null
                {
                    operation.result.fileSize = StrConv.toDisplaySize(info.size)
                    operation.result.metadata = #move info
                }
            }

            // A thumbnail needs only its document; rescanning the folder for every tile is quadratic.
            if not operation.includeNeighbors do
                return

            let folder = Path.directoryName(operation.result.absoluteFileName)
            if not folder do
                return
            let files = catch Directory.enumerateFiles(folder)
            {
                return
            }

            for file in files where not file.isDirectory() do
                operation.result.folderFiles.add(file.fullName)

            operation.result.folderFiles.sort(func(a, b) => Utf8.compare(a.toSlice(), b.toSlice(), .Latin1NoCase))
        },
                owner)
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
