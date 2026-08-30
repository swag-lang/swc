#global if WINDOWS
#global private

// A loaded library resolves its exports, and closing it clears the owner without requiring drop.
#test
{
    var library = expect NativeLibrary.load("kernel32.dll")
    Swag.assert(library.isOpen())
    Swag.assert(library.symbol("GetCurrentProcessId") != null)
    Swag.assert(library.symbol("MissingSymbolThatDoesNotExist") == null)

    library.close()
    Swag.assert(!library.isOpen())
    Swag.assert(library.symbol("GetCurrentProcessId") == null)

    // Cleanup is idempotent so an early explicit close and the owner drop compose safely.
    library.close()
}
