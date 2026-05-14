#global fileprivate

func(T) comparePair(values: [2] T, cb: func||(T, T)->s32)->bool
{
    return cb(values[0], values[1]) < 0
}

func semaTest001()
{
    let values = [7, 3]
    let result = comparePair(values, func(left, right: s32)->s32 => left <=> right)

    #assert(#typeof(result) == bool)
}
