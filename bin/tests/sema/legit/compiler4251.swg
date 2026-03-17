#global fileprivate // swc-option sema-only
#global skip
#test
{
    const X = "abcd"
    let x   = X[ to ]
    @assert(x == "abcd")
}
