#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Marked blanks keep the text where its caret is: a space is a dot over its own advance and a
// tabulation a line to its stop, so the words after them do not move in a proportional face.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 96)

    let ed = RichEditCtrl.create(&host.root, {0, 0, 360, 96})
    ed.style.setFont(host.theme.createDefaultFont(15), .Regular)
    ed.setFlags(.ReadOnly | .DrawBlanks)
    ed.setText("Words  with two spaces\n\tafter a tab\nend  ")

    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "richedit.blanks")
}
