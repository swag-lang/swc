using Gui

struct ActionFile {}

impl ActionFile
{
    newCmdId("SaveAsImage")
    newCmdId("SaveAsLinkedImage")
    newCmdId("OpenImage")
    newCmdId("UpdateLinkedImage")
    newCmdId("UnlinkImage")
    newCmdId("DupCapture")
    newCmdId("RenameCapture")
    newCmdId("CopyImage")
    newCmdId("DeleteCapture")
    newCmdId("CaptureFileLocation")
    newCmdId("LinkedFileLocation")
    newCmdId("NewImage")
    newCmdId("NewFromClipboard")
    newCmdId("FileDetails")
}

impl IActionUI for ActionFile
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()

        switch cxt.id
        {
        case .NewImage:
            evt.updatedFields |= .Name
            evt.name          = appStrings().act_NewImage

        case .NewFromClipboard:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_NewFromClipboard
            evt.disabled      = !Clipboard.hasImage()

        case .SaveAsImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_SaveAsImage
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.SaveAs)

        case .SaveAsLinkedImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_SaveAsLinkedImage
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.Export)

        case .OpenImage:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_OpenImage
            evt.icon          = main.theme().icon(.OpenFile)

        case .UpdateLinkedImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_UpdateLinkedImage
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.Update)

        case .UnlinkImage:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_UnlinkImage
            evt.disabled      = !capture or capture.linkedImage.length == 0

        case .DeleteCapture:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_Delete
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.Remove)

        case .DupCapture:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_Duplicate
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.Duplicate)

        case .RenameCapture:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_Rename
            evt.disabled      = !capture

        case .CopyImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_CopyImageToClipboard
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.Copy)

        case .CaptureFileLocation:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_LocateCaptureFile
            evt.disabled      = !capture
            evt.icon          = main.theme().icon(.OpenFile)

        case .LinkedFileLocation:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_LocateLinkedImage
            evt.disabled      = !capture or capture.linkedImage.isEmpty()
            evt.icon          = main.theme().icon(.Link)

        case .FileDetails:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_FileDetails
            evt.disabled      = !capture
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        switch cxt.id
        {
        case .NewImage:
            main.newImage()

        case .NewFromClipboard:
            main.newCapture(Clipboard.getImage())

        case .SaveAsImage:
            main.saveAsImage()

        case .SaveAsLinkedImage:
            main.saveAsImage(linked: true)

        case .OpenImage:
            main.openImage()

        case .UnlinkImage:
            let res = MessageDlg.confirm(main.surface!, appStrings().msg_RemoveAssociation)
            if res == MessageDlg.BtnYes
            {
                capture.linkedImage.clear()
                capture.changed        = true
                capture.linkedUpToDate = false
                main.saveCapture(capture)
                main.recentWnd.updateRecent()
            }

        case .UpdateLinkedImage:
            if capture.linkedImage.length == 0
            {
                main.saveAsImage(linked: true)

                // `saveAsImage` returns silently when the user cancels the dialog, leaving
                // `linkedImage` empty; only mark up-to-date and persist when a linked path
                // was actually set, otherwise we'd record a linked image that doesn't exist.
                if capture.linkedImage.length != 0
                {
                    capture.linkedUpToDate = true
                    main.saveCapture(capture)
                    main.recentWnd.updateRecent()
                }

                break
            }

            if main.editorOptions.confirmLinkedOverwrite
            {
                var txt = Format.toString("This will overwrite the original image.\n")
                txt += Format.toString("<i>%</i>", capture.linkedImage)

                var opt: MessageDlgOptions
                opt.onCreated = func|main|(dlg)
                {
                    let chk = CheckButton.create(dlg.surface!.view(), "Do not ask again", {0, 0, 100, 40})
                    chk.sigChanged += func|main|(btn) { main.editorOptions.confirmLinkedOverwrite = !btn.isChecked() }
                    dlg.setExtension(chk)
                }

                if MessageDlg.confirm(main.surface!, txt, options: opt) != Dialog.BtnYes do
                    break
            }

            Cursor.activateWait()
            var img = capture.toImage()
            main.doSaveImage(capture, &img, capture.linkedImage)

        case .DeleteCapture:
            let res = MessageDlg.confirm(main.surface!, appStrings().msg_DeleteCaptures)
            if res == MessageDlg.BtnYes
            {
                if main.libraryMode do
                    main.libWnd.removeSelected()
                else do
                    main.recentWnd.removeRecent()
            }

        case .DupCapture:
            Cursor.activateWait()
            main.saveCapture(capture)

            let file = Library.newFileName()
            catch File.duplicate(file, capture.file) else {}

            let newCapture = catch Capture.load(file)

            // `Capture.load` is fallible; `catch` swallows a failure and yields null,
            // so guard before dereferencing to avoid a null crash and abort the duplication.
            if !newCapture
            {
                MessageDlg.error(main.surface!, appStrings().msg_FailedDuplicate)
                break
            }

            let loaded = newCapture
            loaded.file        = file
            loaded.linkedImage = ""
            loaded.changed     = true
            catch loaded.save() else {}
            Memory.delete(loaded)
            g_Library.addFile(file)

            let dupCapture = catch main.recentWnd.addRecent(file, true, true)
            Memory.delete(dupCapture)

        case .RenameCapture:

            // Snapshot the values now: 'capture' may be a library preview that the modal
            // loop could invalidate, but the file path and current title stay valid.
            let file = capture.file.toString()

            var editOptions: EditDlgOptions
            editOptions.title   = appStrings().dlg_TitleRenameCapture
            editOptions.message = "Capture name"
            editOptions.text    = capture.title
            let dlg = EditDlg.createSingleLine(main.surface!, editOptions)
            if dlg.doModal() == Dialog.BtnOk do
                main.setCaptureTitle(file, dlg.text())

        case .CopyImage:
            if main.libraryMode do
                main.copyLibraryImage(capture.file)
            else do
                capture.copyAll()

        case .CaptureFileLocation:
            if !Env.showInFileExplorer(capture.file) do
                MessageDlg.error(main.surface!, appStrings().msg_FailedLocateCapture)

        case .LinkedFileLocation:
            if !Env.showInFileExplorer(capture.linkedImage) do
                MessageDlg.error(main.surface!, appStrings().msg_FailedLocateLinked)

        case .FileDetails:

            func addLine(lt: *Wnd, title, val: String)
            {
                let wnd = Wnd.create'StackLayoutCtrl(lt)
                wnd.mode            = .Left
                wnd.position.height = 20
                let lbl1 = Label.create(wnd, title, {0, 0, 100, 0})
                lbl1.setTextHorizontalAlignment(.Left)
                let lbl2 = Label.create(wnd, val, {0, 0, 1000, 0})
                lbl2.setTextHorizontalAlignment(.Left)
            }

            let dlg = Dialog.create(main.surface!, 600, 400, title: appStrings().dlg_TitleDetails, flags: .Border | .CloseButton | .Resizable)
            dlg.addButton(Gui.strings().dlg_Close, Dialog.BtnCancel, true)
            let lt = StackLayoutCtrl.create(dlg)
            lt.dockStyle = .Center
            lt.padding   = 5
            addLine(lt, appStrings().ui_DetailFile, Format.toString("%", capture.file))
            if capture.linkedImage != null do
                addLine(lt, appStrings().ui_DetailLinkedImage, Format.toString("%", capture.linkedImage))
            addLine(lt, appStrings().ui_DetailImageSize, Format.toString("%x%", capture.width, capture.height))
            if capture.capturedAt.isValid() do
                addLine(lt, appStrings().ui_DetailCapturedAt, Format.toString("%", capture.capturedAt))
            if !capture.sourceApplication.isEmpty() do
                addLine(lt, appStrings().ui_DetailApplication, capture.sourceApplication)
            if !capture.sourceWindowTitle.isEmpty() do
                addLine(lt, appStrings().ui_DetailWindowTitle, capture.sourceWindowTitle)
            if !capture.sourceExecutable.isEmpty() do
                addLine(lt, appStrings().ui_DetailExecutable, capture.sourceExecutable)
            if !capture.sourceWindowClass.isEmpty() do
                addLine(lt, appStrings().ui_DetailWindowClass, capture.sourceWindowClass)
            if !capture.tags.isEmpty()
            {
                var tags: String
                for tag in capture.tags
                {
                    if !tags.isEmpty() do
                        tags += ", "
                    tags += tag[]
                }

                addLine(lt, appStrings().ui_DetailTags, tags)
            }

            if capture.rating do
                addLine(lt, appStrings().ui_DetailRating, ratingLabel(capture.rating))
            addLine(lt, appStrings().ui_DetailFileSize, StrConv.toDisplaySize(catch File.info(capture.file).size))
            lt.computeLayout()
            discard dlg.doModal()
        }

        return true
    }
}

// Offers exactly the image formats the pixel codec registry supports, so a codec added
// to `bin/std` appears in both file dialogs without a change here. The format spelling
// `preferred` names is listed first, because the dialog preselects the first filter and
// appends its first extension to a name typed without one.
private func addImageFilters(opt: *FileDlgOptions, formats: const [..] ImageFormat, preferred = ".png")
{
    for &format in formats where format.matches(preferred) do
        opt.filters.add({format.name, format.extensions})
    for &format in formats where !format.matches(preferred) do
        opt.filters.add({format.name, format.extensions})
}

impl MainWnd
{
    mtd openImage()
    {
        var opt: FileDlgOptions
        with opt
        {
            .state             = &me.fileDlgState
            .mode              = .SelectFile
            .title             = appStrings().dlg_TitleLoadImage
            .confirmButtonText = appStrings().dlg_BtnLoad
            .shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
            .shortcuts.add({Env.SpecialDirectory.UserPictures, appStrings().ui_MyImages})
            .shortcuts.add({Env.SpecialDirectory.CommonPictures, appStrings().ui_CommonImages})
        }

        let formats = Image.decodableFormats()
        addImageFilters(&opt, formats.toSlice())

        let dlg = FileDlg.create(.surface!, opt)
        if dlg.doModal() != Dialog.BtnOk do
            return

        let img = catch Image.load(dlg.selectedPath()) as err
        if err != null do
            MessageDlg.error(.surface!, appStrings().msg_FailedLoadImage, err)
        else do
            .newCapture(img, dlg.selectedPath())
    }

    // Whether a dragged payload holds anything this editor can open.
    //
    // A file counts when one of the registered decoders claims its name, which is the same
    // question [[Pixel.Image.load]] asks; a payload with no such file counts when the source
    // offers a bitmap of its own. Reading it is deliberately cheap: this runs on every mouse
    // move of a drag hovering the window, and the image itself is only decoded on the drop.
    mtd hasDroppableImage(data: *DragData)->bool
    {
        for &f in data.files
        {
            if Image.canLoad(f.toString()) do
                return true
        }

        return data.hasImage()
    }

    // Opens everything a dropped payload holds, one capture per image.
    //
    // Files win over the bitmap when both are offered: a file keeps the capture linked to what
    // it came from, and the bitmap beside it is the same picture with that link thrown away.
    mtd openDroppedImages(data: *DragData)
    {
        var opened = false
        for &f in data.files where Image.canLoad(f.toString())
        {
            .loadExternalImage(f)
            opened = true
        }

        if opened do
            return

        let img = data.image()
        if img do
            .newCapture(img[])
    }

    // Returns the file name the capture travels under when it leaves the application.
    //
    // A library file is a capture, which nothing outside this application reads; what a folder, a
    // mail client or a document editor is handed has to be a picture. The name is the capture's,
    // so the file that lands where it is dropped is recognizable rather than a generated
    // identifier.
    mtd dragFileName(capture: *Capture)->String
    {
        var result = String.from(Path.fileNameWithoutExtension(capture.file) orelse "capture")
        result += ".png"
        return result
    }

    // Fills `data` with what a drag of `capture` carries: the picture, and the same picture as a
    // file named after the capture.
    //
    // Both are offered because the two useful destinations want different things — a folder or a
    // mail draft takes the file, a picture editor pastes the bitmap — and neither costs anything
    // until a target asks for it. The file has no path: it is a name and the bytes behind it, and
    // those bytes are encoded on that first request.
    //
    // `img` is borrowed by the producer, so it has to outlive the gesture the payload is used for.
    mtd fillDragData(data: *DragData, capture: *Capture, img: *Image)
    {
        data.setImage(img[])
        data.addContent(.dragFileName(capture), func|img|()
        {
            var opt: Png.EncodeOptions
            opt.compressionLevel = .BestSpeed
            return catch img.encodeToBytes("drag.png", opt)
        })
    }

    // Hands the current capture to another application, as a file and as a picture.
    //
    // `from` is the window the gesture started on, which is what the desktop anchors it to. A drag
    // released over nothing costs nothing and leaves nothing behind, where writing the PNG to the
    // temporary folder up front left one file per abandoned gesture.
    //
    // This blocks until the drop, so the caller must have forgotten its own press first: the
    // button comes back up inside the loop the desktop runs and no release event follows.
    mtd dragOutCapture(from: *Wnd)
    {
        let capture = .getCapture()
        if !capture do
            return

        Cursor.activateWait()
        var img = capture.toImage()

        var data: DragData
        .fillDragData(&data, capture, &img)
        discard from.startDrag(&data, .Copy)
    }

    mtd doSaveImage(capture: *Capture, img: *Image, nameFile: String)
    {
        // Which encoder runs is the registry's decision, taken from the extension.
        // Only the two formats that expose encoding options are tuned here; every other
        // encoder writes with its own defaults.
        let ext               = Path.lowercaseExtension(nameFile)
        var optImg: #null any = null
        var optPng: Png.EncodeOptions
        var optJpg: Jpg.EncodeOptions

        if ext == ".png"
        {
            optPng.compressionLevel = Core.Compress.Deflate.CompressionLevel.BestSpeed
            optPng.filtering        = false
            optImg                  = optPng
        }
        elif ext == ".jpg" or ext == ".jpeg"
        {
            optJpg.quality = 95
            optImg         = optJpg
        }

        var md: ImageMetadata
        md.tag   = CaptureFileMetadataTag
        md.value = capture.file.toSlice()
        img.metadata.add(md)

        catch img.save(nameFile, optImg) as err
        if err != null
        {
            MessageDlg.error(.surface!, appStrings().msg_FailedSaveFile, err)
            return
        }

        capture.changed        = true
        capture.linkedUpToDate = true
        .saveCapture(capture)
        if @isset(.recentWnd) do
            .recentWnd.updateRecent()

        let txt = Format.toString("Image <url>%</url> has been saved", nameFile)
        let emb = InfoBar.create(.editWnd.view!, txt, .Information, flags: .Bottom | .AutoDismiss)
        emb.label.sigLinkActivated += func(lbl, msg) { Env.showInFileExplorer(msg) }
    }

    mtd saveAsImage(linked = false)
    {
        let fileName = .getSaveAsImageName()
        if fileName.isEmpty() do
            return
        .doSaveAsImage(fileName, linked)
    }

    mtd getSaveAsImageName()->String
    {
        let capture = .getCapture()!

        var opt: FileDlgOptions
        with opt
        {
            .state             = &me.fileDlgState
            .mode              = .CreateFile
            .title             = appStrings().dlg_TitleSaveAsImage
            .confirmButtonText = appStrings().dlg_BtnSave
            .shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
            .shortcuts.add({Env.SpecialDirectory.UserPictures, appStrings().ui_MyImages})
            .shortcuts.add({Env.SpecialDirectory.CommonPictures, appStrings().ui_CommonImages})
            .initialName = Path.fileNameWithoutExtension(capture.file) orelse ""
        }

        // A capture already linked to an image keeps that format preselected, so saving
        // it again does not silently change the format. PNG otherwise: it is lossless,
        // and a capture is text and flat color far more often than it is a photograph.
        var preferred = capture.linkedImage.toString()
        if !Image.canSave(preferred) do
            preferred = ".png"

        let formats = Image.encodableFormats()
        addImageFilters(&opt, formats.toSlice(), preferred)

        let dlg = FileDlg.create(.surface!, opt)
        if .inPlaceEdit do
            dlg.surface?.setTopMost()
        if dlg.doModal() != Dialog.BtnOk do
            return ""
        return dlg.selectedPath()
    }

    mtd doSaveAsImage(fileName: String, linked = false)
    {
        let capture = .getCapture()!
        Cursor.activateWait()
        var img = capture.toImage()
        if linked do
            capture.linkedImage = fileName
        .doSaveImage(capture, &img, fileName)
    }

    mtd newImage()
    {
        let dlg = Dialog.create(.surface!, 350, 235, title: appStrings().act_NewImage)
        dlg.addButton(appStrings().dlg_BtnCreate, Dialog.BtnOk, true)
        dlg.addButton(Gui.strings().dlg_Cancel, Dialog.BtnCancel)
        let edit0 = EditCtrl.create(dlg, appStrings().ui_Width, "512", {90, 12}, flags: .RightAligned)
        let edit1 = EditCtrl.create(dlg, appStrings().ui_Height, "512", {90, 47}, flags: .RightAligned)
        edit0.edit.setUnsignedIntegerRange(16, 4096)
        edit1.edit.setUnsignedIntegerRange(16, 4096)
        if dlg.doModal() != Dialog.BtnOk do
            return

        let {w, ?, ?} = catch StrConv.parseS32(edit0.edit.text())
        let {h, ?, ?} = catch StrConv.parseS32(edit1.edit.text())
        var img       = Image.create(w != 0 ? w : 512, h != 0 ? h : 512, .RGB8)
        img.fill(Argb.White)
        .newCapture(img, sourceKind: .BlankCanvas)
    }
}
