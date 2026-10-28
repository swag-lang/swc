#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func awaitFormat(window: *MainWindow)
{
    var watch: Time.Stopwatch
    watch.start()
    while not window.formatTask.isDone() and watch.elapsedMilliseconds() < 30000 do
        Threading.Thread.sleep(10'ms)
    Swag.assert(window.formatTask.isDone())
    window.finishFormat()
}

// The actual formatter updates the editor in one undo step, without losing later edits.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.setLiveEdit(false)
    const Source = "func value()->s32\n{\nreturn 42\n}\n"
    window.editor.setText(Source)
    Swag.assert(window.runCommand(PrismCommands.FormatSource))
    Swag.assert(window.formatStatus == .Working and window.reading() == appStrings().ui_Formatting)
    awaitFormat(window)
    Swag.assert(window.formatStatus == .Done and window.reading() == appStrings().ui_Formatted)
    Swag.assert(window.editor.text().contains("\n    return 42\n"))
    window.editor.undo()
    Swag.assert(window.editor.text() == Source)
    window.format()
    window.editor.setText("// A newer edit\n")
    awaitFormat(window)
    Swag.assert(window.formatStatus == .Changed)
    Swag.assert(window.editor.text() == "// A newer edit\n")
}

// A syntax error keeps the original source and exposes the formatter diagnostics in the sheet.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.setLiveEdit(false)
    const Source = "func broken( {\n"
    window.editor.setText(Source)
    window.format()
    awaitFormat(window)
    Swag.assert(window.formatStatus == .Failed and window.reading() == appStrings().ui_FormatFailed)
    Swag.assert(window.editor.text() == Source)
    window.refreshInformation()
    Swag.assert(window.infoSheet.text().contains(appStrings().ui_Formatter))
}
