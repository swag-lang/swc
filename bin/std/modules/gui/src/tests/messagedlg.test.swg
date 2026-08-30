#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A message made of one run that wrapping cannot break, which is what a path or a URL is.
func unbreakableMessage()->String
{
    var result: retval
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
    defer host.shutdown()

    let message  = unbreakableMessage()
    with let dlg = MessageDlg.create(&host.surface, message.toString(), {})
    {
        .addButton("Ok", Dialog.BtnOk, true)
    }

    Swag.assert(dlg.label.textHorizontalAlignment == .Left)
    Swag.assert(dlg.contentView != null)
    Swag.assert(dlg.label.parent!.parent == dlg.contentView)

    // The box sizes itself as it opens, so its rectangle is read from inside the modal loop.
    var width = 0'f32
    host.app.sigFrame += func|host = &host, dlg, width = &width|(app)
    {
        discard app
        if width[] != 0 do
            return
        width[] = dlg.surface!.position.width
        Swag.assert(host.clickModalButton(Dialog.BtnOk))
    }

    Swag.assert(dlg.doModal() == Dialog.BtnOk)

    // The message runs several times the width of the host; the box it opened does not.
    Swag.assert(width != 0)
    Swag.assert(width <= 700)
}
