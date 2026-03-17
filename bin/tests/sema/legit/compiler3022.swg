#global fileprivate
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
