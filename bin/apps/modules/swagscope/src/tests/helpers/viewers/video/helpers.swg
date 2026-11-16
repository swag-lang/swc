#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Viewers

// Opens a track choice through the command a reader can use from the lens.
func openVideoLensChoice(host: *Testing.HeadlessHost, view: *Film.Panel, title: string)
{
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Video", host.theme)
    view.describeLens(&entries)
    for &entry in results.sections[0]!.entries where entry.title == title
    {
        entry.run!()
        return
    }

    Swag.require(false, title)
}
