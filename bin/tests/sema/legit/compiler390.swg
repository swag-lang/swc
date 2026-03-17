#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    @assert(@countof({1, 2}) == 2)
}
