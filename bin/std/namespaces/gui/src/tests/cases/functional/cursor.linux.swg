#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

// Thread cursor selection without a native surface must not open an X11 connection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let before = LinuxDesktop.current()
    Cursor.activateWait()
    Cursor.activate(Cursor.from(.Hidden))
    Cursor.activate(Cursor.from(.Arrow))
    Swag.require(LinuxDesktop.current() == before)
}
