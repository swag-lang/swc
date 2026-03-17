#global fileprivate // swc-option sema-only
#global skip
enum RGB
{
    R
    G
    B
}

func toto()->RGB => RGB.R
#test
{
    @assert(toto() == RGB.R)
}
