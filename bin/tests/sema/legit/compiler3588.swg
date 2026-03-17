#global fileprivate // swc-option sema-only
#global skip
var x: func||()

//#[Swag.PrintBc]
#test
{
    let a = x == null
    @assert(a == true)

    let b = x != null
    @assert(b == false)
}
