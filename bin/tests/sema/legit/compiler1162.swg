#global fileprivate
#global skip
const TOTO = false
#if TOTO
{
    #test
    {
        @assert(false)
    }
}
