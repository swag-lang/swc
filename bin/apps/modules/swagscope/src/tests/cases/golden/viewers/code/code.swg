#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Builds the Swag document the highlighting test lexes.
//
// This one fixture is written at run time instead of being stored under `datas`: the compiler
// collects every '.swg' below `src` with no exception for a test folder, so a file keeping the
// extension the lexer is selected by would be compiled into the viewer and would publish its
// declarations as part of it.
func swagSampleSource()->String
{
    var result: #returntype
    result += "#global public\n"
    result += "\n"
    result += "using Core\n"
    result += "\n"
    result += "// Swag lexer verification fixture.\n"
    result += "func answer(value: u32)->u32\n"
    result += "{\n"
    result += "    let doubled = value * 2\n"
    result += "    if doubled > 40 do\n"
    result += "        return doubled + 2\n"
    result += "    return 0\n"
    result += "}\n"
    return result
}

#[Swag.TestTag("golden")]
#test
{
    let source   = swagSampleSource()
    let fileName = Gui.Testing.tempFilePath("scope-code-", ".swg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = Code.Panel.create(&host.root, fileName)
    view.setZoom(150)
    Swag.require(view.zoomPercent == 150)
    view.setZoom(100)
    view.resize(640, 360)
    view.applyLayout()
    view.editor.lexAll()

    // RichEdit stores logical line breaks as LF, which is what the document was written with.
    let content  = view.editor.textAndStyles()
    let expected = source.toRuneArray()
    Swag.require(Utf8.fromUnicode(content.text.toSlice()) == Utf8.fromUnicode(expected.toSlice()))
    var colored: bool
    for style in content.styles where style != 0
    {
        colored = true
        break
    }

    Swag.require(colored)

    var image = host.renderSettled(view)
    assertScopeImageGolden(&image, "viewer.code.document")
}

// The lens as a reader meets it over a code file: opened empty, then typed into, then asked for
// actions with `>`.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-lens-", ".swg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, swagSampleSource())

    var host: Testing.HeadlessHost
    host.setup(1100, 700)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(1100, 700)
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)

    for query, i in ["", "doub", ">"]
    {
        window.lens.open(query)
        host.finishAnimations()

        // Typed into, the lens answers first with the lines of the file that hold the query.
        if i == 1
        {
            let first = unwrap window.lens.results.sections[0]
            Swag.require(first.label == appStrings().lens_InFile and first.count >= 1)
            Swag.require(Utf8.contains(first.entries[0].title.toString(), "doubled") and first.entries[0].lead.length)
        }

        var image = host.render(window)
        assertScopeImageGolden(&image, i == 0 ? "showcase.lens.empty" : (i == 1 ? "showcase.lens.query" : "showcase.lens.actions"))
        window.lens.close()
        host.finishAnimations()
    }

    // A colon and a number go to that line.
    window.lens.open(":3")
    host.finishAnimations()
    let goTo = unwrap window.lens.results.sections[0]
    Swag.require(goTo.label == appStrings().lens_InFile and goTo.entries[0].title == Format.toString(appStrings().lens_GoToLine, 3))
    window.lens.close()
    host.finishAnimations()
}
