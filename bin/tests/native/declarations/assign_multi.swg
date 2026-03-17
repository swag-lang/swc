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
