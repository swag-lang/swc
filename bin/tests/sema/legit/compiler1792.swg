#global fileprivate // swc-option sema-only
#global skip
enum A
{
    AA
    BB
}

#test
{
    alias TOTO = A
    @assert(TOTO.AA == 0)
}
