#global fileprivate // swc-option sema-only
#global skip
//#global skip
#test
{
    var toto = false
    let r    = #ref &toto
    while r
    {
        @assert(false)
    }
}
