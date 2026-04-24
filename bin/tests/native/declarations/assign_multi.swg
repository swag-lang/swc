#global fileprivate // 

#test
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
    @assert(a == 2)
    @assert(b == 2)
}


#test
{
    var a: s32
    var b: s32
    a, ?, b = 1
    @assert(a == 1)
    @assert(b == 1)
}


#test
{
    var a: f32
    var b: s32
    a, b = 1
    @assert(a == 1.0)
    @assert(b == 1)
}


#test
{
    var a: [*] u8
    a += 1
    a -= 1
    @assert(a == null)
}

#test
{
    var data: [3] u16 = [10, 20, 30]
    var ptr           = &data[0]
    var count         = 0'u64

    ptr, count += 1
    @assert(dref ptr == 20)
    @assert(count == 1)

    ptr, count += 1
    @assert(dref ptr == 30)
    @assert(count == 2)

    ptr, count -= 1
    @assert(dref ptr == 20)
    @assert(count == 1)
}
