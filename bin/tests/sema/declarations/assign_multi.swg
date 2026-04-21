#global fileprivate

#test
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
}

#test
{
    var a: s32
    var b: s32
    a, ?, b = 1
}

#test
{
    var a: f32
    var b: s32
    a, b = 1
}

#test
{
    var ptr: const [*] u16
    var count: u64
    ptr, count += 1
    ptr, count -= 1
}
