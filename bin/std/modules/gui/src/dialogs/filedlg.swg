#global public
using Core, File, Directory

enum FileDlgMode
{
    CreateFile
    SelectOneFile
    SelectMultiFiles
    SelectFolder
}

struct FileDlgState
{
    position:                Math.Rectangle
    curFolder:               String
    folderHistory:           Array'String
    columnWidthName:         s32 = 200
    columnWidthModified:     s32 = 150
}

struct FileDlgOptions
{
    title:          string
    btnOkName:      string
    openFolder:     string
    editName:       string
    drivePane       = true
    mode:           FileDlgMode = SelectOneFile
    filters:        Array'{ name: string, extensions: string }
    shortcuts:      Array'{ type: Core.Env.SpecialDirectory, name: string }
    state:          *FileDlgState
}

// Thin modal wrapper around the reusable 'FileBrowserCtrl' composite.
struct FileDlg
{
    using dialog:     Dialog
    browser:          *FileBrowserCtrl
    dlgOptions:       FileDlgOptions
}

impl IWnd for FileDlg
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        // The browser saves the folder/column widths; the dialog owns the position.
        if .dlgOptions.state do
            .dlgOptions.state.position = .surface.position
    }
}

fileprivate impl FileDlg
{
    mtd onNewFolder()
    {
        let folderName: String = "New Folder"

        with let dlg = EditDlg.createSingleLine(me.surface)
        {
            .edit.setText(folderName)
            .edit.selectAll()
            .edit.setNote("Folder name")
            .surface.setTitle("Folder Name")
            .surface.center(me.surface)
        }

        let browser = .browser
        dlg.sigPressedButton = func|dlg, browser|(fdlg, btnid)
        {
            if btnid != Dialog.BtnOk do
                return true

            var folderName = dlg.edit.text
            folderName.trim()
            if folderName.isEmpty()
            {
                dlg.edit.selectAll()
                dlg.edit.setFocus()
                return false
            }

            if !Path.isValidFileName(folderName)
            {
                MessageDlg.error(dlg.surface, "Invalid folder name")
                dlg.edit.selectAll()
                dlg.edit.setFocus()
                return false
            }

            let path = Path.combine(browser.curFolder, folderName.toString())
            if Directory.exists(path)
            {
                MessageDlg.error(dlg.surface, "Folder already exists")
                dlg.edit.selectAll()
                dlg.edit.setFocus()
                return false
            }

            return true
        }

        if dlg.doModal() != Dialog.BtnOk do
            return

        if !.browser.createFolder(dlg.edit.text.toString()) do
            MessageDlg.error(.surface, "Cannot create folder")
    }
}

impl FileDlg
{
    // Creates the file dialog (own OS surface), hosting a FileBrowserCtrl.
    func create(from: *Surface, opt: FileDlgOptions = {})->*FileDlg
    {
        let dlg = Wnd.create'FileDlg()
        dlg.fromSurface = from
        dlg.dlgOptions  = opt

        with let srf = dlg.createSurface(from, 100, 100, 700, 500)
        {
            .setSurfaceFlags(add: .Sizeable)
            .minSize = {400, 400}

            if opt.title do
                .setTitle(opt.title)
            else
            {
                #[Swag.Complete]
                switch opt.mode
                {
                case CreateFile:
                    .setTitle("Create File")
                case SelectOneFile:
                    .setTitle("Select File")
                case SelectMultiFiles:
                    .setTitle("Select Files")
                case SelectFolder:
                    .setTitle("Select Folder")
                }
            }
        }

        dlg.addButton(opt.btnOkName orelse "Ok", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.backgroundStyle = .Window
        srf.setSurfaceFlags(remove: .CloseBtn)

        // Host the reusable browser composite.
        let fileDlg = dlg
        with dlg.browser = FileBrowserCtrl.create(srf.getView(), opt)
        {
            .dockStyle = .Center
            .sigAccept += func|fileDlg|(b)
            {
                fileDlg.validateId(Dialog.BtnOk)
            }
            .sigNewFolder += func|fileDlg|(b)
            {
                fileDlg.onNewFolder()
            }
        }

        dlg.sigPressedButton = func|dlg|(bdlg, id)
        {
            if id == Dialog.BtnOk
            {
                let selName = dlg.browser.getSelectedName()
                if selName == null
                {
                    dlg.browser.editFile.selectAll()
                    dlg.browser.editFile.setFocus()
                    return false
                }

                if dlg.dlgOptions.mode == .CreateFile and File.exists(selName)
                {
                    let res = MessageDlg.confirm(dlg.surface, "This file already exists.", "Do you want to replace it ?")
                    return res == Dialog.BtnYes
                }
            }

            return true
        }

        dlg.applyLayout()

        // Restore the saved surface position if any.
        if opt.state and !opt.state.position.isEmpty() do
            srf.setPosition(opt.state.position)
        else do
            srf.center(from)

        return dlg
    }

    // Get the first selection (full path)
    mtd getSelectedName()->String
    {
        return .browser.getSelectedName()
    }

    // Get all selections (full paths)
    mtd getSelectedNames()->Array'String
    {
        return .browser.getSelectedNames()
    }
}
