#global fileprivate // swc-option sema-only
#global skip
var a = ["0", "1.0"]

//#[Swag.PrintBc]
#test
{
    @assert(a[0] == "0")
    @assert(a[1] == "1.0")
}
