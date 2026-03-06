#global fileprivate
#global skip
#test
{
    let x = #curlocation
    @assert(x.lineStart == 2)
}
