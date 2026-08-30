#global private     //

#[Swag.Strict]
alias StrictKindOfAny = any

// ============================================================
// Swag.kindOf result type with a plain any
// ============================================================

#test
{
    var a: any = 0's32
    var b      = Swag.kindOf(a)
    #assert(#typeof(b) == typeinfo)
    Swag.assert(#typeof(b) == typeinfo)
}

// ============================================================
// Swag.kindOf with Swag.makeAny — primitive types
// ============================================================

#test
{
    var x: s32
    var a: any = Swag.makeAny(&x, s32)
    var b      = Swag.kindOf(a)
    Swag.assert(b == s32)
}

#test
{
    var x: f32
    var a: any = Swag.makeAny(cast(*void) &x, f32)
    var b      = Swag.kindOf(a)
    Swag.assert(b == f32)
}

#test
{
    var x: u8
    var a: any = Swag.makeAny(&x, u8)
    Swag.assert(Swag.kindOf(a) == u8)
}

#test
{
    var x: u16
    var a: any = Swag.makeAny(&x, u16)
    Swag.assert(Swag.kindOf(a) == u16)
}

#test
{
    var x: u32
    var a: any = Swag.makeAny(&x, u32)
    Swag.assert(Swag.kindOf(a) == u32)
}

#test
{
    var x: u64
    var a: any = Swag.makeAny(&x, u64)
    Swag.assert(Swag.kindOf(a) == u64)
}

#test
{
    var x: s8
    var a: any = Swag.makeAny(&x, s8)
    Swag.assert(Swag.kindOf(a) == s8)
}

#test
{
    var x: s16
    var a: any = Swag.makeAny(&x, s16)
    Swag.assert(Swag.kindOf(a) == s16)
}

#test
{
    var x: s64
    var a: any = Swag.makeAny(&x, s64)
    Swag.assert(Swag.kindOf(a) == s64)
}

#test
{
    var x: f64
    var a: any = Swag.makeAny(&x, f64)
    Swag.assert(Swag.kindOf(a) == f64)
}

#test
{
    var x: bool
    var a: any = Swag.makeAny(&x, bool)
    Swag.assert(Swag.kindOf(a) == bool)
}

#test
{
    var x: rune
    var a: any = Swag.makeAny(&x, rune)
    Swag.assert(Swag.kindOf(a) == rune)
}

// ============================================================
// Swag.kindOf with struct types
// ============================================================

struct Point { x: s32, y: s32 }

#test
{
    var p      = Point{1, 2}
    var a: any = Swag.makeAny(&p, Point)
    Swag.assert(Swag.kindOf(a) == Point)
}

// ============================================================
// Swag.kindOf with enum types
// ============================================================

enum Kind: u8 { A = 1, B = 2 }

alias KindAlias       = Kind

#[Swag.Strict]
alias StrictKindAlias = Kind

#assert(#kindof(KindAlias) == u8)
#assert(#kindof(StrictKindAlias) == u8)

#test
{
    var k      = Kind.A
    var a: any = Swag.makeAny(&k, Kind)
    Swag.assert(Swag.kindOf(a) == Kind)
}

#test
{
    var k      = cast(StrictKindAlias) Kind.B
    var a: any = Swag.makeAny(&k, StrictKindAlias)
    Swag.assert(Swag.kindOf(a) == StrictKindAlias)
    Swag.assert(cast(StrictKindAlias) a == cast(StrictKindAlias) Kind.B)
}

// ============================================================
// Swag.kindOf — reassigning the any changes the kind
// ============================================================

#test
{
    var x: s32 = 1
    var y: f64 = 2.0
    var a: any = Swag.makeAny(&x, s32)
    Swag.assert(Swag.kindOf(a) == s32)
    a = Swag.makeAny(&y, f64)
    Swag.assert(Swag.kindOf(a) == f64)
}

// ============================================================
// Swag.kindOf with string
// ============================================================

#test
{
    var s: string = "hello"
    var a: any    = Swag.makeAny(&s, string)
    Swag.assert(Swag.kindOf(a) == string)
}

#test
{
    var x:   s32 = 42
    var raw: any = Swag.makeAny(&x, s32)
    let boxed    = (&raw)[as StrictKindOfAny]
    var b        = Swag.kindOf(boxed)
    #assert(#typeof(b) == typeinfo)
    Swag.assert(b == s32)
}

#test
{
    var text: string = "alias-kind"
    var raw:  any    = Swag.makeAny(&text, string)
    let boxed        = (&raw)[as StrictKindOfAny]
    Swag.assert(Swag.kindOf(boxed) == string)
}
