#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global private

#[Swag.CallingConvention(.C)]
alias UnaryDouble = func(f64)->f64

#[Swag.TestTag("integration.native")]
#test
{
    var library = expect NativeLibrary.load("libm.so.6")
    Swag.require(library.isOpen())
    let address = library.symbol("cos_suffix"[until 3])
    Swag.require(address != null)
    let cosine = cast(UnaryDouble, address)
    let result = cosine(0)
    Swag.require(result == 1)
    Swag.require(library.symbol("") == null)
    Swag.require(library.symbol("swag_missing_native_library_symbol") == null)

    library.close()
    Swag.require(not library.isOpen())
    Swag.require(library.symbol("cos") == null)
    library.close()
}

#[Swag.TestTag("integration.native")]
#test
{
    for path in ["", "/swag_missing_native_library.so"]
    {
        var failure: Swag.Error
        discard catch NativeLibrary.load(path) as failure
        Swag.require((failure.value() is Swag.SystemError))
    }
}
