#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

#test
{
    let path = Testing.tempFilePath("vault launch é-", ".container-data")
    defer discard catch File.delete(path)
    discard expect File.writeAllText(path, "container")
    let executable = Env.executablePath()
    let directory  = unwrap Path.directoryName(path)
    let arguments  = [executable, "--hide", "swag.sandbox", "swag.smoke=40", directory, path.toString()]
    let selected   = vaultLaunchFile(arguments)
    Swag.require(Path.equals(selected, path))
    Swag.require(vaultLaunchFile([executable]).isEmpty())
    Swag.require(vaultLaunchFile([executable, "--hide", "swag.smoke=40"]).isEmpty())
}

// The first-launch driver choice is offered only for a container that authenticates without access.
#test
{
    var window: MainWindow
    window.operation.kind = .CheckEmptyAccess
    for password in ["", "password"]
    {
        let path = Testing.tempFilePath("vault launch access-", ".container-data")
        defer discard catch File.delete(path)
        var volume = expect Volume.create(path, password, MinimumSize)
        volume.close()

        window.operation.path = path
        window.runOperation()
        if password.count == 0
        {
            Swag.require(window.operation.error.isEmpty())
        }
        else
        {
            let outcome = window.operation.error.value()
            if outcome is Error as error do
                Swag.require(error.kind == .PasswordOrDamaged)
            else do
                Swag.require(false, "protected launch should refuse empty access")
        }
    }
}

// A saved hidden-volume protection request still needs its access before opening a writable drive.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let path   = Testing.tempFilePath("vault launch hidden-", ".container-data")
    window.privacyMode = false
    window.startupVaults.add(StartupVault{path, "", false, false, true})

    window.openForAutomaticMount(path)
    Swag.require(window.chosenLockedPath() == path.toString())
    Swag.require(window.protectHiddenOnMount and window.operation.kind == .None)
}
