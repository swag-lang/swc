#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// RGB runs survive escapes, reset, newlines, and multibyte text without shifting styles.
#test
{
    var output: CompilerOutput
    output.parse("plain \x1B[38;2;90;180;255mré\nrax\x1B[0m end")
    Swag.assert(output.text.toString() == "plain ré\nrax end")
    Swag.assert(output.colors.count == 1)
    Swag.assert(output.colors[0] == Color.fromRgb(90, 180, 255))
    Swag.assert(output.runs.count == 3)
    Swag.assert(output.runs[0].style == 0)
    Swag.assert(output.runs[1].style == 1)
    Swag.assert(output.runs[2].style == 0)

    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()
    let editor = RichEditCtrl.create(&host.surfaceWnd)
    editor.setFlags(.ReadOnly)
    editor.setLexer(&output)
    output.show(editor)
    editor.lexAll()
    Swag.assert(editor.text().toString() == output.text.toString())
    Swag.assert(editor.runeAt({lineIndex: 0, charPosInLine: 7}).char == 'é')
    Swag.assert(editor.runeAt({lineIndex: 0, charPosInLine: 7}).style == 1)
    Swag.assert(editor.runeAt({lineIndex: 1, charPosInLine: 0}).style == 1)
    Swag.assert(editor.runeAt({lineIndex: 1, charPosInLine: 4}).style == 0)

    host.theme.setLight()
    host.notify(.ThemeChanged)
    var expected = output.colors[0]
    expected.ensureContrast(editor.themeColors().richEdit_Bk, 4.5)
    Swag.assert(editor.styles[1].colFg == expected)

    output.parse("next result")
    output.show(editor)
    Swag.assert(output.colors.isEmpty())
    Swag.assert(editor.text().toString() == "next result")
    Swag.assert(editor.runeAt({}).style == 0)
}

// Plain output, repeated colors, default foreground, and incomplete controls are safe.
#test
{
    var output: CompilerOutput
    output.parse("  0 | mov rax, [rsp+8]\n  1 | ret\n")
    Swag.assert(output.text.toString() == "  0 | mov rax, [rsp+8]\n  1 | ret\n")
    Swag.assert(output.colors.isEmpty())

    output.parse("\x1B[38;2;90;180;255ma\x1B[38;2;90;180;255mb\x1B[39mc\x1B[")
    Swag.assert(output.text.toString() == "abc")
    Swag.assert(output.colors.count == 1)
    Swag.assert(output.runs[1].style == 1)
    Swag.assert(output.runs[2].style == 0)

    output.parse("value\x1B[38;2;999;0;0m text\x1B[K\x1B")
    Swag.assert(output.text.toString() == "value text")
    Swag.assert(output.colors.isEmpty())
}
