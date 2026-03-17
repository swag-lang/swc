#global fileprivate // swc-option sema-only

var A: func(s32)
#assert(#nameof(#typeof(A)) == "func(s32)")
var B: func(s32, bool)
#assert(#nameof(#typeof(B)) == "func(s32, bool)")
var C: func(s32, bool)->string
#assert(#nameof(#typeof(C)) == "func(s32, bool)->string")
var D: func(s32, string)->*s32 throw
#assert(#nameof(#typeof(D)) == "func(s32, string)->*s32 throw")
var E: func||(s32)
#assert(#nameof(#typeof(E)) == "func||(s32)")
var F: func||(s32, bool)
#assert(#nameof(#typeof(F)) == "func||(s32, bool)")
var G: func||(s32, bool)->string
#assert(#nameof(#typeof(G)) == "func||(s32, bool)->string")
var H: func||(s32, string)->*s32 throw
#assert(#nameof(#typeof(H)) == "func||(s32, string)->*s32 throw")

var I: func() = null
var J: func(...) = null
var K: func(s32...) = null
#assert(#nameof(#typeof(I)) == "func()")
#assert(#nameof(#typeof(J)) == "func(...)")
#assert(#nameof(#typeof(K)) == "func(s32...)")

var A0: func(a: s32)
#assert(#nameof(#typeof(A0)) == "func(a: s32)")

func PtrMatch0() {}
func PtrMatch1(value: s32) {}
func PtrMatch2(lhs: s32, rhs: bool)->string => "ok"
func PtrMatch4(values: s32...)->s32
{
    var result = 0
    foreach value in values do
        result += value
    return result
}
func PtrMatch5(values: ...)->s32
{
    return cast(s32) @countof(values)
}

#test
{
    let p0: func() = &PtrMatch0
    let p1: func(value: s32) = &PtrMatch1
    let p2: func(s32, bool)->string = &PtrMatch2
    let p4: func(s32...)->s32 = &PtrMatch4
    let p5: func(...)->s32 = &PtrMatch5

    p0()
    p1(10)

    let text = p2(1, true)
    #assert(#typeof(text) == string)

    let total = p4(1, 2, 3)
    #assert(#typeof(total) == s32)

    let count = p5(1, true, "ok")
    #assert(#typeof(count) == s32)
}

#test
{
    var badArity: func() = &PtrMatch1 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var bad0: func(bool) = &PtrMatch1 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var bad1: func(s32)->bool = &PtrMatch1 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var bad3: func(...)->s32 = &PtrMatch4 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var bad4: func(s32...)->s32 = &PtrMatch5 // swc-expected-error {{sema_err_cannot_cast}}
}

var BAD: func(s32) = true // swc-expected-error {{sema_err_cannot_cast}}
