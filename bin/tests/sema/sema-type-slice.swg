#global internal

var A: [..] s32
#assert(#typeof(A) == [..] s32)
#assert(#nameof(#typeof(A)) == "[..] s32")

var B: [..] void // swc-expected-error {{sema_err_bad_slice_element_type}}

#test
{
    var a: [4] s32
    var b: [..] s32 = a

    var c: const [..] u8 = "abc"
    var d: [..] u8 = "abc" // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a2: [3] u8
    var e: [..] u16 = cast([..] u16) a2 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var x: u8
    var pv: [*] void = cast([*] void) &x
    var f: const [..] u8 = cast(const [..] u8) pv

    var s0: [..] u8 = null
    var s1: [..] s32 = s0 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: [3] s32 = [1, 2, 3]
    var s: [..] s32 = a
    @assert(s[0] == 1)
    s[1] = 7
    @assert(a[1] == 7)
}

#test
{
    var c: const [..] u8 = "abc"
    @assert(c[0] == 'a')
    @assert(@countof(c) == 3)
}
