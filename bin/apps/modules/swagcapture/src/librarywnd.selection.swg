impl LibraryWnd
{
    // Moves the selected captures to the recycle bin. The names are snapshotted first:
    // g_Library.removeFile() fires onDeleteFile, whose handler removes entries from
    // .view.items, and deleting from the list being iterated would skip entries and
    // desync the selection.
    mtd removeSelected()
    {
        for name in .selectedFiles() do
            g_Library.removeFile(name.toString())
    }

    // Returns owned copies of the selected, visible file names, so a caller can act on them
    // while refilling the grid moves the items they came from.
    mtd selectedFiles()->Array'String
    {
        var result: #returntype
        for it, i in .view.items where not it.filtered
        {
            if .view.selModel.isSelected(cast(i)) do
                result.add(it.fi.fullName)
        }

        return result
    }

    // Brings the selected captures back from the recycle bin into the library.
    mtd restoreSelected()
    {
        for name in .selectedFiles()
        {
            let dst = Library.restoreFile(name)
            if not dst.isEmpty() do
                g_Library.addFile(dst)
        }

        catch .view.fill()
        .invalidate()
    }

    // Erases the selected captures from the recycle bin for good.
    mtd deleteForeverSelected()
    {
        for name in .selectedFiles() do
            discard catch Capture.deleteFiles(name[])

        catch .view.fill()
        .invalidate()
    }

    mtd moveSelHome()
    {
        if .view.items.isEmpty() do
            return
        .view.setFocusItem(0)
        .view.scrollToFocus()
    }

    mtd moveSelEnd()
    {
        if .view.items.isEmpty() do
            return
        .view.setFocusItem(cast(u32, .view.items.count) - 1)
        .view.scrollToFocus()
    }

    mtd moveSelLeft()
    {
        if .view.items.isEmpty() do
            return
        if .view.focusItem == 0 or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem -= 1
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd moveSelRight()
    {
        if .view.items.isEmpty() do
            return
        if .view.focusItem == .view.items.count - 1 or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem += 1
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd moveSelTop()
    {
        if .view.items.isEmpty() do
            return
        let n = .view.numImagesPerLine()
        if .view.focusItem < n or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem -= n
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd moveSelBottom()
    {
        if .view.items.isEmpty() do
            return
        let n = .view.numImagesPerLine()

        // Use an addition instead of 'items.count - n' so an unsigned underflow
        // (when n > items.count) cannot make the guard pass and jump out of range.
        if .view.focusItem + n >= .view.items.count or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem += n
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd selectedCaptureFiles()->Array'String
    {
        var result: #returntype
        for item, i in .view.items where item.kind == .Capture and .view.selModel.isSelected(cast(i)) do
            result.add(item.fi.fullName)
        return result
    }

    mtd refreshPreviewMetadata(file: String, tags: const *Array'String? = null, favorite: const *bool? = null, rating: const *u8? = null)
    {
        .view.mutexLoaded.lock()
        defer .view.mutexLoaded.unlock()
        for item in .view.allItems where item!.capture and item.fi.fullName == file
        {
            if tags do
                item.capture!.tags = tags[]
            if favorite do
                item.capture!.favorite = favorite[]
            if rating do
                item.capture!.rating = rating[]
        }

        let active = .main.editWnd.getCapture()
        if active and active.file == file
        {
            if tags do
                active.tags = tags[]
            if favorite do
                active.favorite = favorite[]
            if rating do
                active.rating = rating[]
        }

        g_DirtyList = true
        .view.invalidate()
    }

    // Writes the tags, favorite mark, or rating given to the capture saved in `file`, after any
    // pending autosave of it has landed. A null value is left as it is.
    mtd updateMetadata(file: String, tags: const *Array'String? = null, favorite: const *bool? = null, rating: const *u8? = null)
    {
        // The edited capture autosaves in the background; make sure this load reads
        // the latest landed version of the file.
        .main.flushCaptureSave(file)

        catch
        {
            try Capture.updateFileMetadata(file, tags: tags, favorite: favorite, rating: rating)
            .refreshPreviewMetadata(file, tags, favorite, rating)
        }
        {
            MessageDlg.error(unwrap .main.surface, appStrings().msg_FailedSaveMetadata, Swag.err)
        }
    }

    // Asks for the tags of the selected captures and writes them to every one. A single capture
    // starts from its own tags.
    mtd editSelectedTags()
    {
        let files = .selectedCaptureFiles()
        if files.isEmpty() do
            return

        var text: String
        if files.count == 1
        {
            for item in .view.items where item.capture and item.fi.fullName == files[0]
            {
                for tag in item.capture.tags
                {
                    if not text.isEmpty() do
                        text += ", "
                    text += tag[]
                }
            }
        }

        var options: EditDlgOptions
        options.title   = appStrings().dlg_TitleEditTags
        options.message = appStrings().ui_CommaSeparatedTags
        options.text    = text
        let dialog = EditDlg.createSingleLine(unwrap .main.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var tags: Array'String
        for part in Tokenize.split(dialog.text(), ','u8, removeEmpty: true)
        {
            var tag = String.from(part)
            tag.trim()
            if tag.isEmpty() do
                continue
            var exists = false
            for own in tags where Utf8.compare(own.toSlice(), tag, .Latin1NoCase) == 0 do
                exists = true
            if not exists do
                tags.add(#move tag)
        }

        for file in files do
            .updateMetadata(file, tags: &tags)
    }

    mtd toggleSelectedFavorite()
    {
        let files    = .selectedCaptureFiles()
        var favorite = false
        for item, i in .view.items
        {
            if item.capture and .view.selModel.isSelected(cast(i)) and not item.capture.favorite do
                favorite = true
        }

        for file in files do
            .updateMetadata(file, favorite: &favorite)
    }

    mtd rateSelected(value: u8)
    {
        for file in .selectedCaptureFiles() do
            .updateMetadata(file, rating: &value)
    }

    mtd exportCapture(file: String, folder: String) fail
    {
        // The exported media must include edits a background save is still writing.
        .main.flushCaptureSave(file)

        let capture = try Capture.load(file)
        defer Memory.delete(capture)

        var name  = String.from(Path.fileNameWithoutExtension(file) orelse "capture")
        capture.editView = .main.editWnd.editView
        switch capture.media
        {
        case .Video:
            name += ".mp4"
            try capture.exportVideo(Library.uniqueName(folder, name))

        case .Animation:
            name += ".gif"
            try capture.exportAnimation(Library.uniqueName(folder, name))

        case .Picture:
            name += ".png"
            var image = capture.toImage()
            try image.save(Library.uniqueName(folder, name))
        }
    }

    // Asks for a folder and writes each selected capture in its media format.
    // Moves the chosen captures to a folder the user picks: they leave the page, and the library
    // when the folder is outside it.
    mtd moveSelected()
    {
        let files = .selectedFiles()
        if files.isEmpty() do
            return

        let initialFolder = .currentFolder()
        var options: FileDlgOptions
        options.mode              = .SelectFolder
        options.state             = &.main.exportFolderDlgState
        options.initialFolder     = initialFolder
        options.title             = appStrings().dlg_TitleMoveCaptures
        options.confirmButtonText = appStrings().dlg_BtnMove
        let dialog = FileDlg.create(unwrap .main.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        let folder = dialog.selectedPath()
        if folder == initialFolder do
            return

        Cursor.activateWait()
        var failed = false
        for name in files where g_Library.moveTo(name, folder).isEmpty() do
            failed = true

        catch .view.fill()
        .invalidate()
        if failed do
            MessageDlg.error(.main.surface, appStrings().msg_FailedMoveCaptures)
    }

    mtd exportSelected()
    {
        let files = .selectedCaptureFiles()
        if files.isEmpty() do
            return

        let initialFolder = .currentFolder()
        var options: FileDlgOptions
        options.mode              = .SelectFolder
        options.state             = &.main.exportFolderDlgState
        options.initialFolder     = initialFolder
        options.title             = appStrings().dlg_TitleExportCaptures
        options.confirmButtonText = appStrings().dlg_BtnExport
        let dialog = FileDlg.create(unwrap .main.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        Cursor.activateWait()
        for file in files
        {
            discard catch .exportCapture(file, dialog.selectedPath())
            {
                MessageDlg.error(.main.surface, appStrings().msg_FailedExportCaptures, Swag.err)
                return
            }
        }
    }
}
