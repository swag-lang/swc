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
    discard Label.createMarkup(&host.root, "Unmount after no input for <a>15\u00A0minutes</a>, while the drive is idle.", {20, 20, 410, 50}, flags: .WordWrap | .SecondaryText | .LinkActions)
    let disabled = Label.createMarkup(&host.root, "The delay is disabled: <a>30\u00A0minutes</a> before unmounting.", {20, 90, 410, 50}, flags: .WordWrap | .SecondaryText | .LinkActions)
    disabled.setLinksEnabled(false)
    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "label.inline-actions.encre")
}
