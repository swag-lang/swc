#global private

func semaTest001()
{
    const A: any = 1's8
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s8)
    Swag.assert(cast(s8) A == 1's8)
}

func semaTest002()
{
    const A: any = 2's16
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s16)
    Swag.assert(cast(s16) A == 2's16)
}

func semaTest003()
{
    const A: any = 3's32
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s32)
    Swag.assert(cast(s32) A == 3's32)
}

func semaTest004()
{
    const A: any = 4's64
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == s64)
    Swag.assert(cast(s64) A == 4's64)
}

func semaTest005()
{
    const A: any = 5'u8
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u8)
    Swag.assert(cast(u8) A == 5'u8)
}

func semaTest006()
{
    const A: any = 6'u16
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u16)
    Swag.assert(cast(u16) A == 6'u16)
}

func semaTest007()
{
    const A: any = 7'u32
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u32)
    Swag.assert(cast(u32) A == 7'u32)
}

func semaTest008()
{
    const A: any = 8'u64
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == u64)
    Swag.assert(cast(u64) A == 8'u64)
}

func semaTest009()
{
    const A: any = 1.5'f32
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == f32)
    Swag.assert(cast(f32) A == 1.5'f32)
}

func semaTest010()
{
    const A: any = 2.5'f64
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == f64)
    Swag.assert(cast(f64) A == 2.5'f64)
}

func semaTest011()
{
    const A: any = true
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == bool)
    Swag.assert(cast(bool) A == true)
}

func semaTest012()
{
    const A: any = 'Z'
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == rune)
    Swag.assert(cast(rune) A == 'Z')
}

func semaTest013()
{
    const A: any = "abc"
    #assert(#typeof(A) == any)
    Swag.assert(Swag.kindOf(A) == string)
    Swag.assert(cast(string) A == "abc")
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
    Swag.assert(cast(s32) A == 10's32)
    Swag.assert(cast(f32) B == 3.0'f32)
    Swag.assert(cast(s64) C == 4294967296's64)
    Swag.assert(cast(f64) D == 1e40'f64)
}
