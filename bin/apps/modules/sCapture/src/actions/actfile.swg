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
        let main    = cast(*MainWnd) notnull cxt.wnd
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
            evt.icon          = main.theme().icon24(.SaveAs)

        case .SaveAsLinkedImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_SaveAsLinkedImage
            evt.disabled      = !capture
            evt.icon          = main.theme().icon24(.Export)

        case .OpenImage:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_OpenImage
            evt.icon          = main.theme().icon24(.OpenFile)

        case .UpdateLinkedImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_UpdateLinkedImage
            evt.disabled      = !capture
            evt.icon          = main.theme().icon24(.Update)

        case .UnlinkImage:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_UnlinkImage
            evt.disabled      = !capture or capture.linkedImage.length == 0

        case .DeleteCapture:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_Delete
            if main.libraryMode do
                evt.disabled = !main.libWnd.hasSelected()
            else do
                evt.disabled = !capture
            evt.icon = main.theme().icon24(.Remove)

        case .DupCapture:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_Duplicate
            evt.disabled      = !capture
            evt.icon          = main.theme().icon24(.Duplicate)

        case .RenameCapture:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_Rename
            evt.disabled      = !capture

        case .CopyImage:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_CopyImageToClipboard
            evt.disabled      = !capture
            evt.icon          = main.theme().icon24(.Copy)

        case .CaptureFileLocation:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_LocateCaptureFile
            evt.disabled      = !capture
            evt.icon          = main.theme().icon24(.OpenFile)

        case .LinkedFileLocation:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_LocateLinkedImage
            evt.disabled      = !capture or capture.linkedImage.isEmpty()
            evt.icon          = main.theme().icon24(.Link)

        case .FileDetails:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_FileDetails
            if main.libraryMode do
                evt.disabled = !main.libWnd.hasSelected()
            else do
                evt.disabled = !capture
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) notnull cxt.wnd
        let capture = notnull main.getCapture()

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
            let res = MessageDlg.confirm(notnull main.surface, appStrings().msg_RemoveAssociation)
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

                if MessageDlg.confirm(notnull main.surface, txt, options: opt) != Dialog.BtnYes do
                    break
            }

            Cursor.activateWait()
            var img = capture.toImage()
            main.doSaveImage(capture, &img, capture.linkedImage)

        case .DeleteCapture:
            let res = MessageDlg.confirm(notnull main.surface, appStrings().msg_DeleteCaptures)
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
                MessageDlg.error(notnull main.surface, appStrings().msg_FailedDuplicate)
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
            let dlg = EditDlg.createSingleLine(notnull main.surface, editOptions)
            if dlg.doModal() == Dialog.BtnOk do
                main.setCaptureTitle(file, dlg.text())

        case .CopyImage:
            if main.libraryMode do
                main.copyLibraryImage(capture.file)
            else do
                capture.copyAll()

        case .CaptureFileLocation:
            if !Env.showInFileExplorer(capture.file) do
                MessageDlg.error(notnull main.surface, appStrings().msg_FailedLocateCapture)

        case .LinkedFileLocation:
            if !Env.showInFileExplorer(capture.linkedImage) do
                MessageDlg.error(notnull main.surface, appStrings().msg_FailedLocateLinked)

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

            let dlg = Dialog.create(notnull main.surface, 600, 400, title: appStrings().dlg_TitleDetails, flags: .Border | .CloseButton | .Resizable)
            dlg.addButton(Gui.strings().dlg_Ok, Dialog.BtnOk, true)
            let lt = StackLayoutCtrl.create(dlg)
            lt.dockStyle = .Center
            lt.padding   = 5
            addLine(lt, appStrings().ui_DetailFile, Format.toString("%", capture.file))
            if capture.linkedImage != null do
                addLine(lt, appStrings().ui_DetailLinkedImage, Format.toString("%", capture.linkedImage))
            addLine(lt, appStrings().ui_DetailImageSize, Format.toString("%x%", capture.width, capture.height))
            addLine(lt, "<b>File Size</b>", StrConv.toDisplaySize(catch File.info(capture.file).size))
            lt.computeLayout()
            discard dlg.doModal()
        }

        return true
    }
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
            .filters.add({appStrings().flt_Png, ".png"})
            .filters.add({appStrings().flt_Jpg, ".jpg"})
            .filters.add({appStrings().flt_Bmp, ".bmp"})
            .filters.add({appStrings().flt_Tga, ".tga"})
        }

        let dlg = FileDlg.create(notnull .surface, opt)
        if dlg.doModal() != Dialog.BtnOk do
            return

        let img = catch Image.load(dlg.selectedPath()) as err
        if err != null do
            MessageDlg.error(notnull .surface, appStrings().msg_FailedLoadImage, err)
        else do
            .newCapture(img, dlg.selectedPath())
    }

    mtd doSaveImage(capture: *Capture, img: *Image, nameFile: String)
    {
        var optImg: #null any = null
        var optPng: Png.EncodeOptions
        var optJpg: Jpg.EncodeOptions

        if Path.lowercaseExtension(nameFile) == ".png"
        {
            optPng.compressionLevel = Core.Compress.Deflate.CompressionLevel.BestSpeed
            optPng.filtering        = false
            optImg                  = optPng
        }
        elif Path.lowercaseExtension(nameFile) == ".jpg"
        {
            optJpg.quality = 95
            optImg         = optJpg
        }

        var md: ImageMetadata
        md.tag   = "sCapture.File"
        md.value = capture.file.toSlice()
        img.metadata.add(md)

        catch img.save(nameFile, optImg) else
        {
            MessageDlg.error(notnull .surface, appStrings().msg_FailedSaveFile)
            return
        }

        capture.changed        = true
        capture.linkedUpToDate = true
        .saveCapture(capture)
        if @isset(.recentWnd) do
            .recentWnd.updateRecent()

        let txt = Format.toString("Image <url>%</url> has been saved", nameFile)
        let emb = InfoBar.create(notnull .editWnd.view, txt, .Information, flags: .Bottom | .AutoDismiss)
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
        let capture = notnull .getCapture()

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
            .filters.add({appStrings().flt_Png, ".png"})
            .filters.add({appStrings().flt_Jpg, ".jpg"})
            .filters.add({appStrings().flt_Bmp, ".bmp"})
            .filters.add({appStrings().flt_Tga, ".tga"})
        }

        let dlg = FileDlg.create(notnull .surface, opt)
        if .inPlaceEdit do
            dlg.surface?.setTopMost()
        if dlg.doModal() != Dialog.BtnOk do
            return ""
        return dlg.selectedPath()
    }

    mtd doSaveAsImage(fileName: String, linked = false)
    {
        let capture = notnull .getCapture()
        Cursor.activateWait()
        var img = capture.toImage()
        if linked do
            capture.linkedImage = fileName
        .doSaveImage(capture, &img, fileName)
    }

    mtd newImage()
    {
        let dlg = Dialog.create(notnull .surface, 350, 235, title: appStrings().act_NewImage)
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
        .newCapture(img)
    }
}
