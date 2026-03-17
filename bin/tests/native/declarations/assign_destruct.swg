#global fileprivate // 

struct Pair { a: s32; b: bool }

#test
{
    var s: Pair
    var a: s32
    var b: bool
    (a, b) = s
    @assert(a == 0)
    @assert(!b)
}

#test
{
    var s: Pair
    var a: s32
    (a, ?) = s
    @assert(a == 0)
}




