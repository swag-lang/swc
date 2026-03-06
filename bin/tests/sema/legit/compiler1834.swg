#global fileprivate
#global skip
struct TOTO {}

#test
{
    @assert(#typeof(TOTO) == TOTO)
}
