#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var g = 0
    for i in 6 until 8 do
        g += i
    @assert(g == 6 + 7)
}
