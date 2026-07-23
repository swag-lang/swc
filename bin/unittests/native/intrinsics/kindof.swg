#global private     //

#[Swag.Strict]
alias StrictKindOfAny = any

// ============================================================
// @kindof result type with a plain any
// ============================================================

#test
{
    var a: any = 0's32
    var b = @kindof(a)
    #assert(#typeof(b) == typeinfo)
    @assert(#typeof(b) == typeinfo)
}

// ============================================================
// @kindof with @mkany — primitive types
// ============================================================

#test
{
    var x: s32
    var a: any = @mkany(&x, s32)
    var b = @kindof(a)
    @assert(b == s32)
}

#test
{
    var x: f32
    var a: any = @mkany(cast(*void) &x, f32)
    var b = @kindof(a)
    @assert(b == f32)
}

#test
{
    var x: u8
    var a: any = @mkany(&x, u8)
    @assert(@kindof(a) == u8)
}

#test
{
    var x: u16
    var a: any = @mkany(&x, u16)
    @assert(@kindof(a) == u16)
}

#test
{
    var x: u32
    var a: any = @mkany(&x, u32)
    @assert(@kindof(a) == u32)
}

#test
{
    var x: u64
    var a: any = @mkany(&x, u64)
    @assert(@kindof(a) == u64)
}

#test
{
    var x: s8
    var a: any = @mkany(&x, s8)
    @assert(@kindof(a) == s8)
}

#test
{
    var x: s16
    var a: any = @mkany(&x, s16)
    @assert(@kindof(a) == s16)
}

#test
{
    var x: s64
    var a: any = @mkany(&x, s64)
    @assert(@kindof(a) == s64)
}

#test
{
    var x: f64
    var a: any = @mkany(&x, f64)
    @assert(@kindof(a) == f64)
}

#test
{
    var x: bool
    var a: any = @mkany(&x, bool)
    @assert(@kindof(a) == bool)
}

#test
{
    var x: rune
    var a: any = @mkany(&x, rune)
    @assert(@kindof(a) == rune)
}

// ============================================================
// @kindof with struct types
// ============================================================

struct Point { x: s32, y: s32 }

#test
{
    var p = Point{1, 2}
    var a: any = @mkany(&p, Point)
    @assert(@kindof(a) == Point)
}

// ============================================================
// @kindof with enum types
// ============================================================

enum Kind: u8 { A = 1, B = 2 }

alias KindAlias = Kind

#[Swag.Strict]
alias StrictKindAlias = Kind

#assert(#kindof(KindAlias) == u8)
#assert(#kindof(StrictKindAlias) == u8)

#test
{
    var k = Kind.A
    var a: any = @mkany(&k, Kind)
    @assert(@kindof(a) == Kind)
}

#test
{
    var k = cast(StrictKindAlias) Kind.B
    var a: any = @mkany(&k, StrictKindAlias)
    @assert(@kindof(a) == StrictKindAlias)
    @assert(cast(StrictKindAlias) a == cast(StrictKindAlias) Kind.B)
}

// ============================================================
// @kindof — reassigning the any changes the kind
// ============================================================

#test
{
    var x: s32 = 1
    var y: f64 = 2.0
    var a: any = @mkany(&x, s32)
    @assert(@kindof(a) == s32)
    a = @mkany(&y, f64)
    @assert(@kindof(a) == f64)
}

// ============================================================
// @kindof with string
// ============================================================

#test
{
    var s: string = "hello"
    var a: any = @mkany(&s, string)
    @assert(@kindof(a) == string)
}

#test
{
    var x: s32 = 42
    var raw: any = @mkany(&x, s32)
    let boxed = dref cast(*StrictKindOfAny) &raw
    var b = @kindof(boxed)
    #assert(#typeof(b) == typeinfo)
    @assert(b == s32)
}

#test
{
    var text: string = "alias-kind"
    var raw: any = @mkany(&text, string)
    let boxed = dref cast(*StrictKindOfAny) &raw
    @assert(@kindof(boxed) == string)
}
