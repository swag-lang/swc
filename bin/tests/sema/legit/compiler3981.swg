#global fileprivate // swc-option sema-only
#global skip
var G: string

func toto(x: const &string)
{
    @assert(x == "G")
}

//#[Swag.PrintBc]
#test
{
    toto("G")
}
