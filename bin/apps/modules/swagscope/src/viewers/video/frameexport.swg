#global internal
#global namespace Viewers.Film

using Core, Gui, Pixel

impl Panel
{
    mtd const hasPausedFrame()->bool
    {
        return .hasFrame and not .playing and not .awaitingFrame and not .thumbnail and not .retireRequested
    }

    mtd copyFrame()
    {
        .startFrameExport(.frameIndex)
    }

    mtd promptSaveFrame()
    {
        let surface = .surface
        if not surface or not .hasPausedFrame() or .frameExporting do
            return

        // Keep the chosen frame even if the panel advances while the file dialog is open.
        let index = .frameIndex
        let stem  = Path.fileNameWithoutExtension(.openFileName) orelse .openFileName.toString()
        let name  = Format.toString("%-frame-%", stem, index + 1)
        with var options: FileDlgOptions
        {
            .mode          = .CreateFile
            .title         = texts().cmd_SaveFrame
            .initialFolder = Path.directoryName(me.openFileName) orelse ""
            .initialName   = name
            .filters.add({texts().ui_FramePng, ".png"})
        }

        let dialog = FileDlg.create(surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            .startFrameExport(index, dialog.selectedPath())
    }

    // Reopens the video to extract the chosen frame at its display dimensions. The worker also
    // encodes and writes a saved frame, while a clipboard image is handed back to the GUI thread.
    private mtd startFrameExport(index: u64, path: string = "")
    {
        if not .hasFrame or .retireRequested or .frameExporting do
            return

        .frameExporting  = true
        .frameExportPath = path
        let width  = .video.displayWidth()
        let height = .video.displayHeight()
        .frameExport.submit(func|view = me, index, width, height|()->Image fail
        {
            let image = try decodeShownFrame(view.openFileName, index, width, height)
            let path  = view.frameExportPath.toString()
            if not path.count do
                return image
            let encoded = try image.encode(path)
            if Swag.isCancelled() do
                return {}

            // Leave the previous file intact until the replacement is complete.
            let folder    = Path.directoryName(path) orelse "."
            let temporary = Path.combine(folder, Format.toString(".swag-frame-%.tmp", Guid128.random()))
            defer discard catch File.delete(temporary)
            try File.writeAllBytes(temporary, encoded)
            if not Swag.isCancelled() do
                try File.move(path, temporary)
            return {}
        })
    }

    mtd finishFrameExport()
    {
        if not .frameExporting or not .frameExport.isDone() do
            return

        .frameExporting = false
        let path   = #move .frameExportPath
        let saving = not path.isEmpty()
        let image  = catch .frameExport.take()
        {
            let title = saving ? texts().ui_FrameSaveFailed : texts().ui_FrameCopyFailed
            .showFrameNotice(title, Viewer.failureText(Swag.err), .Failure)
            return
        }

        if saving do
            .showFrameNotice(texts().ui_FrameSaved, Path.fileName(path) orelse path.toString(), .Done)
        else do
            Clipboard.addImage(image)
    }

    private mtd showFrameNotice(message, detail: string, tone: ToastTone)
    {
        if not .frameToast do
            .frameToast = Toast.create(me)
        .frameToast.show(message, detail, tone)
    }
}
