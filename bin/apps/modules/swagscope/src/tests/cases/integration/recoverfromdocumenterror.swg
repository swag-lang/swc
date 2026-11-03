#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Show a real decoder error, then recover to a valid local document in the same native window.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var brokenFile = Gui.Testing.tempFilePath("scope-broken-", ".png")
    let stateFile  = Gui.Testing.tempFilePath("scope-state-", ".scc")
    defer discard catch File.delete(brokenFile)
    defer discard catch File.delete(stateFile)
    expect File.writeAllBytes(brokenFile, [0x89'u8, 0x50'u8, 0x4E'u8, 0x47'u8, 0'u8, 0xFF'u8])

    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(stateFile)
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1100, 790, surfaceId: "scope-document-recovery")
    let window  = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    surface.show()

    window.openFile(brokenFile, remember: false)
    let errorReady = func|window, &brokenFile|()->bool
    {
        if window.currentFile != brokenFile or
           window.currentView == null or
           window.activeChoiceIndex >= window.instances.count or
           not (window.currentView is ViewerErrorView) do
            return false
        return not window.instances[window.activeChoiceIndex].failureReason.isEmpty()
    }

    var watch: Time.Stopwatch
    watch.start()
    var errorPresented = false
    while watch.elapsedMilliseconds() < 10_000
    {
        app.runFrame()
        if errorReady() and expect Testing.verifyNativePresentation(surface)
        {
            errorPresented = true
            break
        }
        Threading.Thread.sleep(10'ms)
    }
    Swag.assert(errorPresented, "the broken image never reached the native error surface")

    var document = scopeTestDataPath("markdown.images.md", #curlocation)
    Path.normalize(&document)
    window.openFile(document, remember: false)
    let documentReady = func|window, &document|()->bool
    {
        if window.currentFile != document or
           window.currentView == null or
           window.activeChoiceIndex >= window.instances.count do
            return false
        if window.currentView is Markdown.View as view do
            return not view.isLoading() and window.instances[window.activeChoiceIndex].failureReason.isEmpty()
        return false
    }

    watch.restart()
    var documentPresented = false
    while watch.elapsedMilliseconds() < 10_000
    {
        app.runFrame()
        if documentReady() and expect Testing.verifyNativePresentation(surface)
        {
            documentPresented = true
            break
        }
        Threading.Thread.sleep(10'ms)
    }
    if not documentPresented
    {
        Console.println("current=", window.currentFile, " pending=", window.pendingFile,
                        " choices=", window.activeChoiceIndex, "/", window.instances.count)
        for &instance, index in window.instances do
            Console.println("viewer=", window.choices[index].key, " failure=", instance.failureReason,
                            " loading=", instance.isLoading != null and instance.isLoading())
    }
    Swag.assert(documentPresented, "the valid document did not recover in the native window")
}
