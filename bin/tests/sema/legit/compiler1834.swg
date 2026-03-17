#global fileprivate // swc-option sema-only
#global skip
struct TOTO {}

#test
{
    @assert(#typeof(TOTO) == TOTO)
}
