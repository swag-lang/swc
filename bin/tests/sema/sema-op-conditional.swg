#global internal

const A = true
const B = A ? 10 : 10
#assert(B == 10)

#test
{
    var C = false
    var D = C ? 20's32 : 30's16
    #assert(#typeof(D) == s32)
}