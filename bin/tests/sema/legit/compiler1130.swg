#global fileprivate // swc-option sema-only
#global skip
enum TOTO
{
    A
    B
}

//#[Swag.PrintBc]
#test
{
    @assert(@countof(TOTO) == 2)
}
