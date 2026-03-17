#global fileprivate // swc-option sema-only

alias UnaryFn = func(s32)->s32

func addOne(value: s32)->s32
{
    return value + 1
}

var GAddOne: UnaryFn = &addOne

#assert(#typeof(GAddOne) == UnaryFn)

func useGlobalCallback(value: s32)->s32
{
    return GAddOne(value)
}

#test
{
    let cb: UnaryFn = GAddOne
    let value = useGlobalCallback(41)
    #assert(#typeof(cb) == UnaryFn)
    #assert(#typeof(value) == s32)
}
