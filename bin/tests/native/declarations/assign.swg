#global fileprivate // swc-option suite-test






#test
{
    var ptr: [*] s32
    ptr += 1
    var ptr1: const [*] s32
    ptr1 += 1
    @assert(#typeof(ptr) == [*] s32)
    @assert(#typeof(ptr1) == const [*] s32)
}

enum R { A, B }
#test
{
    var a: R
    a = .A
    @assert(a == .A)
}

#test
{
    var a: f32
    a += 1's16
    @assert(a == 1.0)
}

#test
{
    var a: f32
    a = 1
    @assert(a == 1.0)
}

#test
{
    var p: [*] s32
    var i: s32
    p += i
    p = p + i
    p = i + p
    p -= 1
    var d: s64
    d = p - p
    @assert(d == 0)
}




