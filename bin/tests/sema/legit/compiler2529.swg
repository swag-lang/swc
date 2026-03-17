#global fileprivate // swc-option sema-only
#global skip
struct ErrToto {}
func toto()->s64 throw
{
    throw ErrToto{}
    return 555
}

//#[Swag.PrintBc]
#test
{
    var g = 0
    var x = catch toto()
    @assert(@err != null)
}
