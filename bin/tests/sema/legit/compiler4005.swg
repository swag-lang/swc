#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x = "x"
    var y = &x
    dref y = "y"
    @assert(x == "y")
}
