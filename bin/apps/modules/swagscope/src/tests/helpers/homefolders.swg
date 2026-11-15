#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui

// Delivers folder results, including a replacement requested while an older snapshot ran.
func completeHomeFolders(host: *Testing.HeadlessHost, home: *ViewerHome)
{
    for 8 where home.folders.started
    {
        home.folders.task.wait()
        host.pump()
    }

    Swag.require(not home.folders.started)
}
