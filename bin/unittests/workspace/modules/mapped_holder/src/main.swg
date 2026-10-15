using Core, MappedDll

// Maps the sibling library for a compile-time call. When the workspace suite asks for it with a
// hold request, this compiler then stays alive while the suite republishes that library: the
// mapped marker tells the suite the library is mapped, and the request's removal tells this
// compiler the republication is over. An ordinary build makes no request and does not wait.
#run
{
    Swag.assert(mappedDllValue() == 42)
    let output  = Path.combine(Path.directoryName(#curlocation.fileName), "..", "..", "..", ".output")
    let request = Path.combine(output.toString(), "mapped_holder.hold")
    if not File.exists(request.toString()) do
        return

    let marker = Path.combine(output.toString(), "mapped_holder.mapped")
    discard catch File.writeAllText(marker.toString(), "mapped")
    var waited = 0
    while File.exists(request.toString()) and waited < 600
    {
        Threading.Thread.sleep(100'ms)
        waited += 1
    }
}

#main
{
    Swag.print("MAPPED_HOLDER_RAN\n")
}
