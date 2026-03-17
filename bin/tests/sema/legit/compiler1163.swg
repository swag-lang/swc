#global fileprivate // swc-option sema-only
#global skip
const TOTO = false
#if TOTO
{
    func toto()
    {
        @assert(false)
    }
}
#else
{
    func toto() {}
}

#test
{
    toto()
}
