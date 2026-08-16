#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, FileScopePluginApi

// The plugin remains a thin ABI adapter around the reusable GUI control.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_html_adapter_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    let source = "<h1>Reusable HTML</h1><p>Adapter content.</p>"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) @dataof(source), @countof(source)))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    var commands: #null *Wnd
    var details:  String
    var reveal:   #null ViewerRevealMatch
    let wnd = sFileScopePluginCreate(&host.root, &host.root, fileName, ViewerPluginApiVersion, &commands, &details, &reveal)
    @assert(wnd != null)
    @assert(commands == null and reveal != null)
    @assert(Utf8.contains(details.toString(), "HTML"))
}
