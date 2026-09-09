#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func awaitFormat(window: *MainWindow)
{
    var watch: Time.Stopwatch
    watch.start()
    while !window.formatTask.isDone() and watch.elapsedMilliseconds() < 30000 do
        Threading.Thread.sleep(10'ms)
    Swag.assert(window.formatTask.isDone())
    window.finishFormat()
}

// The actual formatter updates the editor in one undo step, without losing later edits.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.liveEdit.setState(.Unchecked)
    const Source = "func value()->s32\n{\nreturn 42\n}\n"
    window.editor.setText(Source)
    host.click(window.formatButton.localToSurface(Math.Point{20, 18}))
    Swag.assert(window.formatStatus == .Working and window.spinner.isVisible())
    awaitFormat(window)
    Swag.assert(window.formatStatus == .Done and !window.spinner.isVisible())
    Swag.assert(Utf8.indexOf(cast(const [..] u8) window.editor.text().toString(), "\n    return 42\n") != Swag.U64.Max)
    window.editor.undo()
    Swag.assert(window.editor.text().toString() == Source)
    window.format()
    window.editor.setText("// A newer edit\n")
    awaitFormat(window)
    Swag.assert(window.formatStatus == .Changed)
    Swag.assert(window.editor.text().toString() == "// A newer edit\n")
}

// A syntax error keeps the original source and exposes the formatter diagnostics.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.liveEdit.setState(.Unchecked)
    const Source = "func broken( {\n"
    window.editor.setText(Source)
    window.format()
    awaitFormat(window)
    Swag.assert(window.formatStatus == .Failed and !window.spinner.isVisible())
    Swag.assert(window.editor.text().toString() == Source)
    Swag.assert(!window.status.toolTip.isEmpty())
}
