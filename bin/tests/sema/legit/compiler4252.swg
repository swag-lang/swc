#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = "abcd"
    let v = 2
    let y = x[ until v]
    @assert(y == "ab")
}
