#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global private

#[Swag.CallingConvention(.C)]
alias UnaryDouble = func(f64)->f64

#[Swag.TestTag("integration.native")]
#test
{
    var library = expect NativeLibrary.load("libm.so.6")
    Swag.assert(library.isOpen())
    let address = library.symbol("cos_suffix"[until 3])
    Swag.assert(address != null)
    let cosine = cast(UnaryDouble, address)
    let result = cosine(0)
    Swag.assert(result == 1)
    Swag.assert(library.symbol("") == null)
    Swag.assert(library.symbol("swag_missing_native_library_symbol") == null)

    library.close()
    Swag.assert(not library.isOpen())
    Swag.assert(library.symbol("cos") == null)
    library.close()
}

#[Swag.TestTag("integration.native")]
#test
{
    for path in ["", "/swag_missing_native_library.so"]
    {
        var failure: Swag.Error
        discard catch NativeLibrary.load(path) as failure
        Swag.assert((failure.value() is Swag.SystemError))
    }
}
