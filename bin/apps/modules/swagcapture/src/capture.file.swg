impl Capture
{
    // Marks the capture as modified and out of step with its linked image, and refreshes the
    // editor and the recent strip, except during an interactive drag.
    mtd hasChanged()
    {
        .changed        = true
        .linkedUpToDate = false

        // During an interactive form drag this runs twice per mouse move (undo() +
        // pushUndo()). The full-view invalidate here would repaint every form and the
        // recent-thumbnail strip each frame, defeating the partial invalidate the
        // interactive gestures do (GizmoRect.apply, the body drag and the create drag
        // in Capture.mouse). Skip the heavy refresh while dragging; it is done once
        // when the drag ends (see Capture.mouse / endInteractiveMove).
        if .interactiveMove do
            return

        // A form that just left the capture loses its retained rendering here, before
        // its memory can be recycled by a later allocation.
        .pruneFormCaches()

        let editView = .editView
        if not editView do
            return
        editView.invalidate()
        editView.main.captureHasChanged()
    }

    // Called once when an interactive form move/resize ends, to refresh the toolbar
    // state / recent strip / full view that hasChanged() skipped during the drag.
    mtd endInteractiveMove()
    {
        if not .interactiveMove do
            return
        .interactiveMove = false
        .hasChanged()
    }

    private func sccId(text: string)->Guid128
    {
        var result: Guid128
        let valid = Guid128.tryParse(text, &result)
        Swag.assert(valid)
        return result
    }

    private func containerKind()->Guid128  => sccId("4a67acc2-5930-4e81-81dc-d12675bc6deb")
    private func tagBinType()->Guid128     => sccId("4d9b85e3-f2ec-4b30-81a9-4d7f6ca7fefa")
    private func pngType()->Guid128        => sccId("9722207f-3561-44a9-bf04-3c8c5238c919")
    private func modelRole()->Guid128      => sccId("6e677ece-9001-44bf-94cd-6721bdd7c339")
    private func previewRole()->Guid128    => sccId("9b5e375d-e615-4a80-8680-6c7c37f94ceb")
    private func backgroundRole()->Guid128 => sccId("648e64f2-ca4b-43ef-8076-6e0dd0523ec5")
    private func originalRole()->Guid128   => sccId("7206ea20-cd74-4832-afa9-0ce33c7699cd")

    // Returns whether `file` is named like a capture.
    //
    // A folder listing asks this once per row, and looking inside a file to answer it costs one
    // open per row: invisible on a warm local disk, and eighteen seconds over a library of seven
    // hundred captures a virus scanner reads through first. A row takes its answer from the name,
    // which is what names are for; the file itself is looked at when one is opened, moved or
    // deleted.
    func isFileName(file: string)->bool => Path.lowercaseExtension(file) == CaptureFileExtension

    // Returns whether `file` is named like a capture and holds one, rather than another
    // document using the SCC extension.
    func isFile(file: string)->bool
    {
        if not isFileName(file) do
            return false

        var reader: Scc.Reader
        catch reader.initialize(file) as openError
        if openError != null do
            return false
        return reader.kind() == containerKind()
    }

    private func(T) encodeValue(value: const *T)->Array'u8 fail
    {
        var output:  ConcatBuffer
        var encoder: Encoder'Write.TagBin
        try encoder.writeAll(&output, value[])
        output.makeLinear()

        var result: retval
        result.add(output.toSlice()!)
        return result
    }

    // The part of the capture the library reads without decoding the image.
    private mtd libraryMetadata()->CaptureLibraryMetadata
    {
        var result: retval
        result.width             = .width
        result.height            = .height
        result.linkedImage       = .linkedImage
        result.linkedUpToDate    = .linkedUpToDate
        result.sourceKind        = .sourceKind
        result.capturedAt        = .capturedAt
        result.sourceApplication = .sourceApplication
        result.sourceExecutable  = .sourceExecutable
        result.sourceWindowTitle = .sourceWindowTitle
        result.sourceWindowClass = .sourceWindowClass
        result.favorite          = .favorite
        result.rating            = .rating
        return result
    }

    // The part of the capture its file stores.
    private mtd fileModel()->CaptureFileModel
    {
        var result: retval
        result.width             = .width
        result.height            = .height
        result.widthOrg          = .widthOrg
        result.heightOrg         = .heightOrg
        result.backImagePos      = .backImagePos
        result.forms             = .forms
        result.nextStepIndex     = .nextStepIndex
        result.nextGroupId       = .nextGroupId
        result.linkedImage       = .linkedImage
        result.linkedUpToDate    = .linkedUpToDate
        result.title             = .title
        result.sourceKind        = .sourceKind
        result.capturedAt        = .capturedAt
        result.sourceApplication = .sourceApplication
        result.sourceExecutable  = .sourceExecutable
        result.sourceWindowTitle = .sourceWindowTitle
        result.sourceWindowClass = .sourceWindowClass
        result.tags              = .tags
        result.favorite          = .favorite
        result.rating            = .rating
        return result
    }

    // Creates a capture from the metadata the library reads without decoding the image.
    private func fromLibraryMetadata(metadata: CaptureLibraryMetadata, manifest: const *Scc.Manifest)->*Capture
    {
        with let result = Memory.new'Capture()
        {
            .width             = metadata.width
            .height            = metadata.height
            .linkedImage       = metadata.linkedImage
            .linkedUpToDate    = metadata.linkedUpToDate
            .title             = manifest.name
            .sourceKind        = metadata.sourceKind
            .capturedAt        = metadata.capturedAt
            .sourceApplication = metadata.sourceApplication
            .sourceExecutable  = metadata.sourceExecutable
            .sourceWindowTitle = metadata.sourceWindowTitle
            .sourceWindowClass = metadata.sourceWindowClass
            .tags              = manifest.tags
            .favorite          = metadata.favorite
            .rating            = metadata.rating
        }

        return result
    }

    // Creates a capture from what its file stored, taking over the forms of `model`.
    private func fromFileModel(model: *CaptureFileModel)->*Capture
    {
        with let result = Memory.new'Capture()
        {
            .width             = model.width
            .height            = model.height
            .widthOrg          = model.widthOrg
            .heightOrg         = model.heightOrg
            .backImagePos      = model.backImagePos
            .forms             = #move model.forms
            .nextStepIndex     = model.nextStepIndex
            .nextGroupId       = model.nextGroupId
            .linkedImage       = #move model.linkedImage
            .linkedUpToDate    = model.linkedUpToDate
            .title             = #move model.title
            .sourceKind        = model.sourceKind
            .capturedAt        = model.capturedAt
            .sourceApplication = #move model.sourceApplication
            .sourceExecutable  = #move model.sourceExecutable
            .sourceWindowTitle = #move model.sourceWindowTitle
            .sourceWindowClass = #move model.sourceWindowClass
            .tags              = #move model.tags
            .favorite          = model.favorite
            .rating            = model.rating
        }

        return result
    }

    mtd save() fail
    {
        if not .changed do
            return

        // A scheduled save may still be writing this same file; land it first so the
        // two writes cannot interleave. Its outcome is superseded by this save.
        discard g_CaptureSaves.flush(.file)

        let job = try .snapshotSave()
        defer Memory.delete(job)
        try writeScc(job)
        .changed = false
    }

    // Schedules the automatic save. The snapshot is taken here, on the interface
    // thread, then a job worker produces the container and atomically replaces the
    // file, so editing never waits on compression or disk.
    mtd scheduleSave() fail
    {
        Swag.assert(not g_CaptureSaves.pending)
        let job = try .snapshotSave()
        g_CaptureSaves.adopt(job)
        job.task.submit(func|job|()
        {
            catch writeScc(job) else do
                job.failed = true
        })

        .changed = false
    }

    // Captures everything a save writes, so the file can be produced without reading
    // the live capture again. Runs on the interface thread: the document model is
    // encoded now because the forms may change under a worker, and the images are
    // copied because a later crop or flatten may replace them while a job still encodes.
    private mtd snapshotSave()->*CaptureSaveJob fail
    {
        var metadata     = .libraryMetadata()
        var model        = .fileModel()
        var profileBytes = try encodeValue(&metadata)
        var modelBytes   = try encodeValue(&model)

        let job = Memory.new'CaptureSaveJob()
        job.file                    = .file
        job.manifest.profileVersion = CaptureProfileVersion
        job.manifest.name           = .title
        job.manifest.createdAt      = .capturedAt
        job.manifest.modifiedAt     = Time.DateTime.now()
        job.manifest.tags           = .tags
        job.manifest.profileData    = #move profileBytes
        job.modelBytes              = #move modelBytes
        job.backImg                 = .backImg
        job.backOrig                = .backImgOriginal
        job.preview                 = .preview
        return job
    }

    // Produces the SCC container from a snapshot and atomically replaces the target
    // file. Runs on a job worker for the automatic save, inline for a synchronous
    // one; it must only touch the snapshot, never the live capture.
    private func writeScc(job: *CaptureSaveJob) fail
    {
        var writer: Scc.Writer
        writer.initialize(containerKind())
        writer.manifest()[] = #move job.manifest

        let typeTagBin     = tagBinType()
        let typePng        = pngType()
        let roleModel      = modelRole()
        let roleBackground = backgroundRole()
        let roleOriginal   = originalRole()
        let rolePreview    = previewRole()
        let codecDeflate   = Scc.deflateCodecId()
        let modelId        = try writer.addChunk(job.modelBytes.toSlice(), {typeId: typeTagBin, roleId: roleModel, codecId: codecDeflate, flags: .Required | .Metadata})

        var variants: Array'Guid128
        if job.backImg.isValid()
        {
            var bytes = try encodeValue(&job.backImg)
            variants.add(try writer.addChunk(bytes.toSlice(), {typeId: typeTagBin, roleId: roleBackground, codecId: codecDeflate, flags: .Required}))
        }

        if job.backOrig.isValid()
        {
            var bytes = try encodeValue(&job.backOrig)
            variants.add(try writer.addChunk(bytes.toSlice(), {typeId: typeTagBin, roleId: roleOriginal, codecId: codecDeflate}))
        }

        if job.preview.isValid()
        {
            var bytes = try job.preview.encodeToBytes("preview.png")
            variants.add(try writer.addChunk(bytes.toSlice(), {typeId: typePng, roleId: rolePreview, flags: .Streamable}))
        }

        var entry: Scc.Entry
        entry.id            = Guid128.random()
        entry.kind          = .File
        entry.name          = Path.fileName(job.file) orelse ""
        entry.tags          = writer.manifest().tags
        entry.primaryChunk  = modelId
        entry.variantChunks = #move variants
        writer.manifest().entries.add(#move entry)
        try writer.saveAtomic(job.file)
    }

    // Loads an SCC capture, or its library metadata and preview when `preview` is set.
    //
    // The caller owns the non-null result and releases it with [[Core.Memory.delete]].
    // `deferPreviewDecode` keeps the encoded preview until it is needed.
    func load(file: String, preview = false, deferPreviewDecode = false)->*Capture fail
    {
        var reader: Scc.Reader
        try reader.initialize(file)
        if reader.kind() != containerKind() do
            fail Core.Errors.InvalidFormatError{}
        if reader.manifest().profileVersion > CaptureProfileVersion do
            fail Core.Errors.InvalidVersion{wantedVersion: CaptureProfileVersion, foundVersion: reader.manifest().profileVersion}

        var capture: *Capture
        if preview
        {
            var decoder: Decoder'Read.TagBin
            let metadata = try decoder.readAll'CaptureLibraryMetadata(reader.manifest().profileData.toSlice())
            defer Memory.delete(metadata)
            metadata.sanitize()
            capture = fromLibraryMetadata(metadata[], reader.manifest())
        }
        else
        {
            let info = reader.findRole(modelRole())
            if not info do
                fail Core.Errors.InvalidFormatError{}
            var bytes = try reader.readChunk(info.id)
            var decoder: Decoder'Read.TagBin
            decoder.flags |= .IgnoreStructFieldError
            let model = try decoder.readAll'CaptureFileModel(bytes.toSlice())
            defer Memory.delete(model)
            capture = fromFileModel(model)

            let diag = decoder.serializer.diag
            capture.loadIssues = diag.fieldErrors +
                                 diag.droppedStreamFields +
                                 diag.unknownTypes +
                                 diag.corruptPayloads

            let background = reader.findRole(backgroundRole())
            if background
            {
                var imageBytes = try reader.readChunk(background.id)
                var imageDecoder: Decoder'Read.TagBin
                let image      = try imageDecoder.readAll'Image(imageBytes.toSlice())
                defer Memory.delete(image)
                capture.backImg = #move image[]
                let imageDiag = imageDecoder.serializer.diag
                capture.loadIssues += imageDiag.fieldErrors +
                                      imageDiag.droppedStreamFields +
                                      imageDiag.unknownTypes +
                                      imageDiag.corruptPayloads
            }

            let original = reader.findRole(originalRole())
            if original
            {
                var imageBytes = try reader.readChunk(original.id)
                var imageDecoder: Decoder'Read.TagBin
                let image      = try imageDecoder.readAll'Image(imageBytes.toSlice())
                defer Memory.delete(image)
                capture.backImgOriginal = #move image[]
                let imageDiag = imageDecoder.serializer.diag
                capture.loadIssues += imageDiag.fieldErrors +
                                      imageDiag.droppedStreamFields +
                                      imageDiag.unknownTypes +
                                      imageDiag.corruptPayloads
            }
        }

        let previewInfo = reader.findRole(previewRole())
        if previewInfo
        {
            var imageBytes = try reader.readChunk(previewInfo.id)
            if deferPreviewDecode do
                capture.previewBytes = #move imageBytes
            else do
                capture.preview = try Image.decode("preview.png", imageBytes.toSlice())
        }

        capture.file = file
        for itf in capture.forms do
            itf.setup(capture)
        reader.close()
        return capture
    }
}
