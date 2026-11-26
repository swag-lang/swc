#global private

func semaTest001()
{
    const A: any = 1_s8
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s8)
    Swag.assert(assume cast(s8, A) == 1_s8)
}

func semaTest002()
{
    const A: any = 2_s16
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s16)
    Swag.assert(assume cast(s16, A) == 2_s16)
}

func semaTest003()
{
    const A: any = 3_s32
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s32)
    Swag.assert(assume cast(s32, A) == 3_s32)
}

func semaTest004()
{
    const A: any = 4_s64
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s64)
    Swag.assert(assume cast(s64, A) == 4_s64)
}

func semaTest005()
{
    const A: any = 5_u8
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u8)
    Swag.assert(assume cast(u8, A) == 5_u8)
}

func semaTest006()
{
    const A: any = 6_u16
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u16)
    Swag.assert(assume cast(u16, A) == 6_u16)
}

func semaTest007()
{
    const A: any = 7_u32
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u32)
    Swag.assert(assume cast(u32, A) == 7_u32)
}

func semaTest008()
{
    const A: any = 8_u64
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u64)
    Swag.assert(assume cast(u64, A) == 8_u64)
}

func semaTest009()
{
    const A: any = 1.5_f32
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == f32)
    Swag.assert(assume cast(f32, A) == 1.5_f32)
}

func semaTest010()
{
    const A: any = 2.5_f64
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == f64)
    Swag.assert(assume cast(f64, A) == 2.5_f64)
}

func semaTest011()
{
    const A: any = true
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == bool)
    Swag.assert(assume cast(bool, A) == true)
}

func semaTest012()
{
    const A: any = 'Z'
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == rune)
    Swag.assert(assume cast(rune, A) == 'Z')
}

func semaTest013()
{
    const A: any = "abc"
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == string)
    Swag.assert(assume cast(string, A) == "abc")
}

func semaTest014()
{
    const A: any? = null
    #assert(#typeof(A) == any?)
    Swag.assert(A == null)
}

func semaTest015()
{
    const A: any = 10
    const B: any = 3.0
    const C: any = 0x1_0000_0000
    const D: any = 1e40
    #assert(#typeof(A) == any)
    #assert(#typeof(B) == any)
    #assert(#typeof(C) == any)
    #assert(#typeof(D) == any)
    Swag.assert(Swag.kindOf(A) == s32)
    Swag.assert(Swag.kindOf(B) == f32)
    Swag.assert(Swag.kindOf(C) == s64)
    Swag.assert(Swag.kindOf(D) == f64)
    Swag.assert(assume cast(s32, A) == 10_s32)
    Swag.assert(assume cast(f32, B) == 3.0_f32)
    Swag.assert(assume cast(s64, C) == 4294967296_s64)
    Swag.assert(assume cast(f64, D) == 1e40_f64)
}
