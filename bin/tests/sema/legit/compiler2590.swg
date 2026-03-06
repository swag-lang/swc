#global fileprivate
#global skip
#test
{
    for x in 10'u8
    {
        @assert(#typeof(x) == u8)
    }

    for x in 10's8
    {
        @assert(#typeof(x) == s8)
    }
}
