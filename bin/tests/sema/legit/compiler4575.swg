#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x = ["1", "23"]
    @assert(x[1, 1] == 51)
}
