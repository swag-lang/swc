#global fileprivate // swc-option sema-only
#global skip
struct Arr
{
    a:   CB
}

impl Arr
{
    mtd add(x: CB)
    {
        me.a = x
    }
}

alias CB = func||()

#test
{
    var arr: Arr
    let x    = func() {}
    arr.add(x)
}
