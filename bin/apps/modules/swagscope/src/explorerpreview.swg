#global internal

using Core, Pixel, Gui

// A single bounded worker produces a thumbnail or an extracted preview, never GUI resources.
struct ExplorerPreview
{
    using operation: Viewer.BackgroundOperation
    path:            String
    archivePath:     String
    entry:           Viewers.Archive.ZipEntry
    service:         ThumbnailService
    image:           Image
    temporary:       String
    error:           String
    index:           u64
    generation:      u64
    opening:         bool
}

impl ExplorerPreview
{
    mtd start(owner: *Wnd)
    {
        .image = {}
        .error.clear()
        .temporary.clear()
        let operation = me
        .submit(func|operation|()
        {
            catch operation.produce() { operation.error = Viewer.failureText(Swag.err) }
        },
                owner)
    }

    private mtd produce() fail
    {
        var file = String.from(.path)
        if not .archivePath.isEmpty()
        {
            var extension = String.from(Path.extension(.path) orelse ".bin")
            if extension.length > 24 do
                extension = ".bin"
            var name = Format.toString("scope-preview-%", Guid64.random())
            name += extension
            if not Path.isValidFileName(name) do
                fail Errors.InvalidFormatError{}
            .temporary = Path.combine(Env.getSpecialDirectory(.Temp), name)
            try Viewers.Archive.Zip.extractEntry(.archivePath, &.entry, .temporary)
            file = .temporary
        }

        defer
        {
            if not .opening and not .temporary.isEmpty()
            {
                catch File.delete(.temporary)
                .temporary.clear()
            }
        }

        if not .opening do
            .image = try .service.render(file)
    }

    mtd opDrop()
    {
        .wait()
        if not .temporary.isEmpty() do
            catch File.delete(.temporary)
    }
}
