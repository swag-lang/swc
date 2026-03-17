#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    {
        var x = 66's64
        x = -x
        @assert(x == -66)
    }
}
