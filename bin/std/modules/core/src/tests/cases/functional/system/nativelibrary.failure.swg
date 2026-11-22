#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectInvalidNativeLibraryPath(path: string)
{
    var error: Swag.Error
    discard catch NativeLibrary.load(path) as error
    Swag.require(error.value() is Errors.BadParameterError)
}

// An unresolved library path reports failure without leaving an owner behind.
#test
{
    let path = CoreTests.makeFilesystemTestPath(Format.toString("core_missing_library_%", Guid64.random()))
    Swag.require(not File.exists(path.toString()))

    var error: Swag.Error
    discard catch NativeLibrary.load(path.toString()) as error
    Swag.require(error.value() != null)
}

// Neither the library path nor an exported symbol name may be truncated at an embedded zero.
#test
{
    #static if WINDOWS
    {
        let library = expect NativeLibrary.load("kernel32.dll")
        Swag.require(library.symbol("GetCurrentProcessId\0ignored") == null)
        expectInvalidNativeLibraryPath("kernel32.dll\0ignored")
    }
    else
    {
        let library = expect NativeLibrary.load("libc.so.6")
        Swag.require(library.symbol("printf\0ignored") == null)
        expectInvalidNativeLibraryPath("libc.so.6\0ignored")
    }
}
