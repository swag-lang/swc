#global fileprivate // swc-option sema-only
#global skip
var T = true
#test
{
    {
        let x = T
        let z = x ^ true
        @assert(z == false)
    }
}
