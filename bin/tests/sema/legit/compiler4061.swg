#global fileprivate // swc-option sema-only
#global skip
//#global skip
#test
{
    var toto = false
    let r    = #ref &toto
    if r and r
    {
        @assert(false)
    }
}
