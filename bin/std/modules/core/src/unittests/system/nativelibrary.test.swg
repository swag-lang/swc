#global if WINDOWS
#global private

// A loaded library resolves its exports, and closing it clears the owner without requiring drop.
#test
{
    var library = expect NativeLibrary.load("kernel32.dll")
    @assert(library.isOpen())
    @assert(library.symbol("GetCurrentProcessId") != null)
    @assert(library.symbol("sViewerSymbolThatDoesNotExist") == null)

    library.close()
    @assert(!library.isOpen())
    @assert(library.symbol("GetCurrentProcessId") == null)

    // Cleanup is idempotent so an early explicit close and the owner drop compose safely.
    library.close()
}
