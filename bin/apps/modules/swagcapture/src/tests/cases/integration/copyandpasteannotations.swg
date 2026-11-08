#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Copy and move a form through the clipboard, then replace and clear a pasted image's contents.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(160, 120)
    let capture = unwrap journey.main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {15, 15}, {65, 60})
    journey.main.sendCommandEvent(ActionCopyPaste.Copy)
    Swag.require(Clipboard.hasTypedValue(#typeof(CaptureClipboardForms)))
    journey.main.sendCommandEvent(ActionCopyPaste.Cut)
    Swag.require(capture.forms.isEmpty())
    journey.main.sendCommandEvent(ActionCopyPaste.Paste)
    Swag.require(capture.forms.count == 1 and Swag.kindOf(capture.forms[0]) == FormShape)

    journey.main.sendCommandEvent(ActionCopyPaste.CopyAsImage)
    Swag.require(Clipboard.hasImage())
    journey.main.sendCommandEvent(ActionCopyPaste.Paste)
    Swag.require(capture.forms.count == 2 and Swag.kindOf(capture.forms[1]) == FormImage)
    let pasted = assume cast(*FormImage, capture.forms[1])
    Swag.require(pasted.image.isValid())

    Clipboard.addImage(Testing.indexedImage(17, 13))
    journey.main.sendCommandEvent(ActionCopyPaste.PasteImageInside)
    Swag.require(pasted.image.width == 17 and pasted.image.height == 13)
    journey.main.sendCommandEvent(ActionEdit.ClearImageInside)
    Swag.require(not pasted.image.isValid())
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(pasted.image.width == 17 and pasted.image.height == 13)

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen pasted picture", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        if main.libraryMode or not opened or opened.file != path or opened.forms.count != 2 do
            return false
        let image = assume cast(*FormImage, opened.forms[1])
        return image.image.width == 17 and image.image.height == 13
    })
}
