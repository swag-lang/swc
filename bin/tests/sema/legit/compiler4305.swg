#global fileprivate
#global skip
#test
{
    var x: func(s32, s32)
    x = func(_1952, ?) {}

    x = func(_1955, a) {}

    x = func(a, ?) {}
}
