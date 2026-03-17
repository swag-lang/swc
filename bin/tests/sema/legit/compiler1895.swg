#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = #curlocation
    @assert(x.lineStart == 2)
}
