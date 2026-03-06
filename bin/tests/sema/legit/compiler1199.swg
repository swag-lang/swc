#global fileprivate
#global skip
struct E
{
    x:   s32
}

#test
{
    var ptr = #typeof(E.x)
}
