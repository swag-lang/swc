#global fileprivate // swc-option suite-test

struct Pair { a: s32; b: bool }

#test
{
    var s: Pair
    var a: s32
    var b: bool
    (a, b) = s
}

#test
{
    var s: Pair
    var a: s32
    (a, ?) = s
}




