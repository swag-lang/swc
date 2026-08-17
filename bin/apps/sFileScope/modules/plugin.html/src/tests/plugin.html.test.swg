#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

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

    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view != null)
    @assert(result.commands == null and result.revealMatch != null)
    @assert(Utf8.contains(result.details.toString(), "HTML"))
}
