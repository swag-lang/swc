using Core, MappedDll

// Maps the sibling library for a compile-time call, then keeps this compiler alive while the
// workspace suite republishes that library. The marker tells the suite the library is mapped;
// its removal tells this compiler the republication is over.
#run
{
    Swag.assert(mappedDllValue() == 42)
    let marker = Path.combine(Path.directoryName(#curlocation.fileName), "..", "..", "..", ".output", "mapped_holder.marker")
    discard catch File.writeAllText(marker.toString(), "mapped")
    var waited = 0
    while File.exists(marker.toString()) and waited < 600
    {
        Threading.Thread.sleep(100'ms)
        waited += 1
    }
}

#main
{
    Swag.print("MAPPED_HOLDER_RAN\n")
}
