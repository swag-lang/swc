#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A message made of one run that wrapping cannot break, which is what a path or a URL is.
func unbreakableMessage()->String
{
    var result: #returntype
    result = "This will overwrite the original image.\n<i>Z:"
    for 8 do
        result += "\\a-very-long-and-unbreakable-directory-name"
    result += "\\picture.png</i>"
    return result
}

// A box is bounded by its maximum width, whatever the message is made of.
//
// Word wrapping has nothing to break a run carrying no space on, so a box holding a path measured
// that path on one line and opened as wide as it: a modal wider than the display, with its own
// actions off the side of it. The message is cut with an ellipsis instead.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 400)

    let message  = unbreakableMessage()
    with let dlg = MessageDlg.create(&host.surface, message.toString())
    {
        .addButton("Ok", Dialog.BtnOk, true)
    }

    Swag.assert(dlg.label.textHorizontalAlignment == .Left)
    Swag.assert(dlg.contentView != null)
    Swag.assert(dlg.label.parent!.parent == dlg.contentView)

    // The box sizes itself as it opens, so its rectangle is read from inside the modal loop.
    var width = 0'f32
    host.app.sigFrame += func|host = &host, dlg, width = &width|(_)
    {
        if width[] != 0 do
            return
        width[] = dlg.surface!.position.width
        let modalButtonClicked = host.clickModalButton(Dialog.BtnOk)
        Swag.assert(modalButtonClicked)
    }

    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnOk)

    // The message runs several times the width of the host; the box it opened does not.
    Swag.assert(width != 0)
    Swag.assert(width <= 700)
}

// A box nobody is going to answer fails the test at once, naming its title and its message,
// instead of spinning until the run times out. The host stands where it stood before the box,
// and a box the test does answer is left alone.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 400)

    let before = host.app.timing.frameCount
    let caught = Swag.catchPanic(func|host = &host|() { MessageDlg.error(&host.surface, "The file is gone") })
    Swag.assert(caught.raised)
    Swag.assert(host.app.timing.frameCount - before <= 2)

    let text = caught.message()
    Swag.assert(Utf8.contains(text, strings().dlg_ErrorTitle))
    Swag.assert(Utf8.contains(text, "The file is gone"))
    Swag.assert(host.app.modalSurfaces.isEmpty() and host.app.inModalLoop == 0)
    Swag.assert(not host.surface.isDisabled)

    // Armed, the same box is answered.
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    MessageDlg.error(&host.surface, "The file is gone")
    Swag.assert(host.autoHandled)
}
