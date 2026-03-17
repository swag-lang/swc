#global fileprivate // swc-option sema-only
#global skip
const TOTO = false
#if TOTO
{
    #assert(false)
}
