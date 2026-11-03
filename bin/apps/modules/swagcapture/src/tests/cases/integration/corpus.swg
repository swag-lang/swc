#global if #command == Swag.CompilerCommand.Test
#global private

using Core.Serialization
using Swag, Core

// Optional load regression over an external, read-only corpus. Only the ordinary test
// sandbox receives application state; the corpus is enumerated and decoded, never saved.
#[Swag.TestTag("integration.capture.corpus")]
#test
{
    let folder = Env.variable("SWAG_CAPTURE_CORPUS")
    Swag.require(not folder.isEmpty())
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    g_Library.files  = expect Library.enumerateSupportedFiles(folder)
    g_Library.loaded = true
    Swag.require(not g_Library.files.isEmpty())
    var watch: Time.Stopwatch
    watch.start()
    main.swapLibraryMode()
    main.libWnd.view.thread.wait()
    host.finishAnimations()
    let view = main.libWnd.view
    Swag.require(view.allItems.count == g_Library.files.count)
    for item in view.allItems do
        Swag.require(item!.loaded)
    Console.print("Corpus items: ", view.allItems.count, "; load ms: ", watch.elapsedMilliseconds(), "\n")

    for 8 do
        discard host.render(main)
    let count = view.allItems.count
    watch.restart()
    for 4
    {
        main.swapLibraryMode()
        main.swapLibraryMode()
        host.finishAnimations()
        discard host.render(main)
        Swag.require(view.allItems.count == count and not g_UpdatingLib)
    }

    Console.print("Four warm library returns with off-screen painting, ms: ", watch.elapsedMilliseconds(), "\n")
}
