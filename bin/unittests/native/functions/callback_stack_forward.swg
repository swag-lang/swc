#global private

#[Swag.CallingConvention(.C)]
alias NativeCall = func(s32, s32, s32, s32, s32, s32, s32, s32, u32, u32)

#[Swag.CallingConvention(.C), Swag.NoInline]
func nativeTarget(a, b, c, d, e, f, g, h: s32, mask, filter: u32)
{
    Swag.assert(a == 1 and b == 2 and c == 3 and d == 4)
    Swag.assert(e == 5 and f == 6 and g == 7 and h == 8)
    Swag.assert(mask == 0x4000 and filter == 0x2600)
}

var callback: NativeCall? = &nativeTarget

#[Swag.NoInline]
func forwardStack(a, b, c, d, e, f, g, h: s32, mask, filter: u32)
{
    let target = callback!
    target(a, b, c, d, e, f, g, h, mask, filter)
}

#test
{
    forwardStack(1, 2, 3, 4, 5, 6, 7, 8, 0x4000, 0x2600)
}
