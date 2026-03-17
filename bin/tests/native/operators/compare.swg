#global fileprivate // 

enum CmpEnum: u16
{
    A = 10
    B = 20
}

var CompareCounter: s32

func touch(flag: bool, delta: s32)->bool
{
    CompareCounter += delta
    return flag
}

#test
{
    var a: *s32 = null
    let b = a == null
    let c = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
    @assert(b)
    @assert(!c)
}

#test
{
    let a = -5 < 12
    let b = 12 <= 12
    let c = 0xFFFF_FFFF_FFFF_FFFF'u64 > 1'u64
    let d = 9'u64 >= 9'u64

    @assert(a)
    @assert(b)
    @assert(c)
    @assert(d)
}

#test
{
    let a = 1 <=> 2
    let b = 2 <=> 1
    let c = 7 <=> 7

    #assert(#typeof(a) == s32)

    @assert(a == -1)
    @assert(b == 1)
    @assert(c == 0)
}

#test
{
    let a = 1.5'f64 < 2.5'f64
    let b = 2.5'f64 <=> 1.5'f64
    let c = 3.25'f64 <=> 3.25'f64

    @assert(a)
    @assert(b == 1)
    @assert(c == 0)
}

#test
{
    let a = CmpEnum.A == CmpEnum.A
    let b = CmpEnum.A != CmpEnum.B

    @assert(a)
    @assert(b)
}

#test
{
    var value0: s32 = 77
    var value1: s32 = 10
    let p0 = &value0
    let p1 = p0
    let p2 = &value1

    @assert(p0 == p1)
    @assert(p0 != p2)
    @assert(p2 != null)
}

#test
{
    CompareCounter = 0
    let a = touch(false, 1) and touch(true, 10)
    let b = touch(true, 100) or touch(true, 1000)

    @assert(!a)
    @assert(b)
    @assert(CompareCounter == 101)
}
