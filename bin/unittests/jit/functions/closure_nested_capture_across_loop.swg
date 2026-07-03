// Closure capture codegen coverage.
//
// An escaping closure keeps its captured variables live across a loop and a set
// of calls, then builds a *nested* closure that re-captures the same variables.
// Reading a capture means dereferencing the closure context pointer (plus the
// capture offset); the context pointer must survive the whole body, including
// loops and calls, and every capture read/write must target the same storage.
//
// This guards the closure-context / capture-address codegen exercised by the
// GUI Properties color editor (Properties.constructColor), whose much larger
// register pressure once made the register allocator reload a stale capture
// context and corrupt the captured pointers.

#global private

struct Box { v: u32; a: u8 }

var g_outer: func||(u32)
var g_inner: func||(u32)
var g_sink:  u32

#[Swag.NoInline]
func blend(x, y: u32)->u32 => ((x << 1) ^ (y >> 1) ^ (x & y)) & 0xFFFFFF

struct Owner { tag: u32; pop: *Box }

impl Owner
{
    // Mirrors the shape of Properties.constructColor's color popup handler:
    // - captures `me` (-> prop), two pointers and two bools;
    // - uses captures early, then runs a loop with calls;
    // - builds a nested closure that re-captures everything and writes back
    //   through the captured pointers.
    mtd build(color: *Box, item: *Box, opaque: bool, keepAlpha: bool)
    {
        let prop = me
        g_outer = func|prop, color, item, opaque, keepAlpha|(unused: u32)
        {
            // Early capture use.
            prop.pop = item
            color.v  = blend(color.v, 1)
            var flag = 0'u32
            if opaque do
                flag |= 1
            if keepAlpha do
                flag |= 2
            item.a = cast(u8) flag

            // Keep the captures live across a loop with calls.
            var acc: [9] u32 = undefined
            var a = 1'u32, b = 2'u32, c = 3'u32, d = 4'u32
            for i in 9
            {
                a      = blend(a, b)
                b      = blend(b, c)
                c      = blend(c, d)
                d      = blend(d, cast(u32) i)
                acc[i] = a ^ b ^ c ^ d ^ flag
            }
            var s = 0'u32
            for i in 9 do
                s ^= acc[i]
            g_sink ^= s

            // Late: nested closure re-capturing the same variables.
            g_inner = func|prop, color, item, opaque, keepAlpha|(val: u32)
            {
                var result = val
                if opaque do
                    result |= 0x10
                elif keepAlpha do
                    result |= 0x20
                color.v = result + prop.tag
                item.v  = result
            }
        }
    }
}

#test
{
    var owner: Owner
    owner.tag = 7
    var color, item: Box
    owner.build(&color, &item, true, false)

    g_outer(0)
    // The early use must have written through the captured pointers.
    @assert(owner.pop == &item)
    @assert(item.a == 1)

    g_inner(5)
    // The nested closure must write through the re-captured pointers.
    @assert(color.v == (5 | 0x10) + 7)
    @assert(item.v == (5 | 0x10))
}
