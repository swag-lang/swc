#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Both inline action states use one rich-string baseline, including the trailing punctuation.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(460, 170)
    host.theme.setDark()
    discard Label.create(&host.root, "Unmount after no input for <url>15\u00A0minutes</url>, while the drive is idle.", {20, 20, 410, 50}, flags: .WordWrap | .SecondaryText | .LinkActions)
    let disabled = Label.create(&host.root, "The delay is disabled: <url>30\u00A0minutes</url> before unmounting.", {20, 90, 410, 50}, flags: .WordWrap | .SecondaryText | .LinkActions)
    disabled.setLinksEnabled(false)
    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "label.inline-actions.encre")
}
