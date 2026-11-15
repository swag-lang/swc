#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Actions use ordinary rich-text wrapping, and disabling links leaves the surrounding prose
// enabled. Activation may replace the label's text without borrowing its old rich-string runs.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 170)
    let label = Label.create(&host.root, "Wait <url>15\u00A0minutes</url> before sleeping.", {20, 20, 230, 100}, flags: .WordWrap | .SecondaryText | .LinkActions)
    var received: String
    label.sigLinkActivated += func|label, &received|(_, target)
    {
        received = target
        label.setText("Wait <url>30\u00A0minutes</url> before sleeping.")
    }

    discard host.renderSettled(&host.root)
    let link = label.firstLinkRect()
    Swag.require(link.width > 0 and link.height > 0 and label.focusPolicy == .Tab)
    var point = link.center()
    point += label.surfaceRect().topLeft()
    host.moveMouse(point)
    host.click(point)
    Swag.require(received == "15\u00A0minutes")
    label.setLinksEnabled(false)
    discard host.renderSettled(&host.root)
    Swag.require(label.isEnabled() and label.focusPolicy == .None)
    point = label.firstLinkRect().center() + label.surfaceRect().topLeft()
    host.moveMouse(point)
    host.click(point)
    Swag.require(received == "15\u00A0minutes")
}

// Tab walks the actions inside a sentence, then resumes the window's normal traversal.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 170)
    let label = Label.create(&host.root, "<url>First action</url> and <url>Second action</url>.", {20, 20, 300, 40}, flags: .LinkActions)
    let next  = PushButton.create(&host.root, "Next", {20, 90, 90, 30})
    var received: String
    label.sigLinkActivated += func|&received|(_, target) { received = target }
    discard host.renderSettled(&host.root)
    label.setFocus()
    host.keyPress(.Enter)
    Swag.require(received == "First action")
    host.keyPress(.Tab)
    host.keyPress(.Space)
    Swag.require(received == "Second action")
    host.keyPress(.Tab, .Shift)
    host.keyPress(.Enter)
    Swag.require(received == "First action")
    host.keyPress(.Tab)
    host.keyPress(.Tab)
    Swag.require(next.hasFocus())
    label.updateFlags(remove: .LinkActions)
    Swag.require(label.focusPolicy == .None)
}

// A Papier sentence uses the link role only for its active action. Disabling it removes that
// color while leaving the paragraph in secondary ink; both glyphs and underline become dim.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    host.theme.setLight()
    let label        = Label.create(&host.root, "Retry after <url>3\u00A0minutes</url>.", {20, 20, 280, 60}, flags: .SecondaryText | .LinkActions)
    let active       = host.renderSettled(&host.root)
    var activePixels = 0'u32
    for y in active.height
    {
        for x in active.width where active.pixelColor(x, y) == host.theme.colors.url_Text do
            activePixels += 1
    }

    Swag.require(activePixels > 0)
    label.setLinksEnabled(false)
    let disabled = host.renderSettled(&host.root)
    for y in disabled.height
    {
        for x in disabled.width do
            Swag.require(disabled.pixelColor(x, y) != host.theme.colors.url_Text)
    }
}
