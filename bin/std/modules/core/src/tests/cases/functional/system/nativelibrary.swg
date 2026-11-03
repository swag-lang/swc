#global if WINDOWS and #command == Swag.CompilerCommand.Test
#global private

// A loaded library resolves its exports, and closing it clears the owner without requiring drop.
#test
{
    var library = expect NativeLibrary.load("kernel32.dll")
    Swag.require(library.isOpen())
    Swag.require(library.symbol("GetCurrentProcessId") != null)
    Swag.require(library.symbol("MissingSymbolThatDoesNotExist") == null)

    library.close()
    Swag.require(not library.isOpen())
    Swag.require(library.symbol("GetCurrentProcessId") == null)

    // Cleanup is idempotent so an early explicit close and the owner drop compose safely.
    library.close()
}
