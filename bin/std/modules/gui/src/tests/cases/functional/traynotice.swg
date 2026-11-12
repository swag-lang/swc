#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A tray notice keeps its option and close button inside the card and emits both outcomes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let notice = unwrap TrayNotice.open(host.surface, "Still running", "Open it from the notification area.",
                                         "Do not show again")
    Swag.require(notice.surface != &host.surface)
    let card = notice.children[0].surfaceRect()
    let choice = unwrap notice.optionCheck
    let check = choice.surfaceRect()
    let close = notice.closeButton.surfaceRect()
    Swag.require(check.x >= card.x and check.right() <= card.right() and check.bottom() <= card.bottom())
    Swag.require(close.x >= card.x and close.right() <= card.right() and close.bottom() <= card.bottom())

    var checked: bool
    var dismissed: bool
    notice.sigOptionChanged += func|checked = &checked|(_, value) { checked[] = value }
    notice.sigDismissed += func|dismissed = &dismissed|(_) { dismissed[] = true }
    choice.toggle()
    Swag.require(checked)
    host.fireTimer(notice.timer)
    Swag.require(dismissed and host.app.surfaces.count == 1)
}

// The cross also dismisses a notice without an option, while leaving its caller free to keep
// that preference unchanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let notice = unwrap TrayNotice.open(host.surface, "Saved", "The work is available.")
    Swag.require(notice.optionCheck == null)
    var dismissed: bool
    notice.sigDismissed += func|dismissed = &dismissed|(_) { dismissed[] = true }
    notice.closeButton.sigPressed.call(notice.closeButton)
    host.fireTimer(notice.timer)
    Swag.require(dismissed and host.app.surfaces.count == 1)
}
