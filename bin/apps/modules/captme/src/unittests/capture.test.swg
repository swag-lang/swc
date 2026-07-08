#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Full-screen OS capture is tested without creating a Captme library file:
// sendToEditor=false keeps the result in the real clipboard only.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor = false
    f.main.captureOptions.sendToClipboard = true
    f.main.captureOptions.sendToEditor = false
    f.main.captureOptions.inPlaceEdit = false
    f.main.captureOptions.delay = 0

    f.main.sendCommandEvent(ActionCapture.FullScreen)

    let img = Clipboard.getImage()
    @assert(img.isValid())
    @assert(img.width > 1)
    @assert(img.height > 1)

    f.shutdown()
}
