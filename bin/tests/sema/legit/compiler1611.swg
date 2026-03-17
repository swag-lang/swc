#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    #ast
    {
        return "var x = 1"
    }

    @assert(x == 1)
}
