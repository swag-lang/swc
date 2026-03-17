#global fileprivate // swc-option sema-only
#global skip
#test
{
    const v = "toto la foule"
    let x   = v[5 to 6]
    @assert(x == "la")
}
