#global fileprivate

struct IfElsePoint
{
    x: s32
    y: s32
}

alias IfElseArray = [3] s32
alias IfElseAlias = s32

enum IfElseKind: u16
{
    A = 2
    B = 5
}

#test
{
    func ifElseReturn(flag: bool)->s32
    {
        if flag
        {
            let left = 10
            return left + 1
        }
        else
        {
            let right = 20
            return right + 2
        }
    }

    const V0 = #run ifElseReturn(true)
    const V1 = #run ifElseReturn(false)
    #assert(V0 == 11)
    #assert(V1 == 22)
}

#test
{
    func nestedIfElse(flag0: bool, flag1: bool)->s32
    {
        if flag0
        {
            let base = 100
            if flag1
            {
                let inc = 1
                return base + inc
            }
            else
            {
                let inc = 2
                return base + inc
            }
        }
        else
        {
            let base = 200
            if flag1
            {
                let inc = 3
                return base + inc
            }
            else
            {
                let inc = 4
                return base + inc
            }
        }
    }

    const V0 = #run nestedIfElse(true, true)
    const V1 = #run nestedIfElse(true, false)
    const V2 = #run nestedIfElse(false, true)
    const V3 = #run nestedIfElse(false, false)
    #assert(V0 == 101)
    #assert(V1 == 102)
    #assert(V2 == 203)
    #assert(V3 == 204)
}

#test
{
    func shadowInsideBranches(flag: bool)->s32
    {
        let value = 5
        if flag
        {
            let value = 7
            return value
        }
        else
        {
            let value = 9
            return value
        }
    }

    const V0 = #run shadowInsideBranches(true)
    const V1 = #run shadowInsideBranches(false)
    #assert(V0 == 7)
    #assert(V1 == 9)
}

#test
{
    func nestedBlockInIfElse(flag: bool)->s32
    {
        if flag
        {
            let a = 1
            {
                let b = 2
                return a + b
            }
        }
        else
        {
            let a = 3
            {
                let b = 4
                return a + b
            }
        }
    }

    const V0 = #run nestedBlockInIfElse(true)
    const V1 = #run nestedBlockInIfElse(false)
    #assert(V0 == 3)
    #assert(V1 == 7)
}

#test
{
    func intWidthInit(flag: bool)->s32
    {
        if flag
        {
            let a: s8 = cast(s8) -12
            let b: s16 = cast(s16) (3 * 4)
            return cast(s32) a + cast(s32) b
        }
        else
        {
            let a: u8 = 7'u8
            let b: u16 = cast(u16) (20 + 5)
            return cast(s32) a + cast(s32) b
        }
    }

    const V0 = #run intWidthInit(true)
    const V1 = #run intWidthInit(false)
    #assert(V0 == 0)
    #assert(V1 == 32)
}

#test
{
    func floatInit(flag: bool)->s32
    {
        if flag
        {
            let v: f32 = (1.25'f32 + 0.75'f32) * 10.0'f32
            return cast(s32) v
        }
        else
        {
            let v: f64 = cast(f64) (3 + 2) * 4.0'f64
            return cast(s32) v
        }
    }

    const V0 = #run floatInit(true)
    const V1 = #run floatInit(false)
    #assert(V0 == 20)
    #assert(V1 == 20)
}

#test
{
    func boolRuneInit(flag: bool)->s32
    {
        if flag
        {
            let b = 10 > 5 and !false
            let r: rune = 'A'
            if b
            {
                return cast(s32) r
            }
            else
            {
                return 0
            }
        }
        else
        {
            let b = false or true
            let r: rune = 'z'
            if b
            {
                return cast(s32) r
            }
            else
            {
                return 0
            }
        }
    }

    const V0 = #run boolRuneInit(true)
    const V1 = #run boolRuneInit(false)
    #assert(V0 == 65)
    #assert(V1 == 122)
}

#test
{
    func stringInit(flag: bool)->u32
    {
        if flag
        {
            let s: string = "Hi"
            return cast(u32) s[0] + cast(u32) s[1]
        }
        else
        {
            let s = "Az"
            return cast(u32) s[0] + cast(u32) s[1]
        }
    }

    const V0 = #run stringInit(true)
    const V1 = #run stringInit(false)
    #assert(V0 == 177'u32)
    #assert(V1 == 187'u32)
}

#test
{
    func structInit(flag: bool)->s32
    {
        if flag
        {
            let p: IfElsePoint = {x: 4, y: 7}
            return p.x * 10 + p.y
        }
        else
        {
            let p = IfElsePoint{x: 9, y: 1}
            return p.x * 10 + p.y
        }
    }

    const V0 = #run structInit(true)
    const V1 = #run structInit(false)
    #assert(V0 == 47)
    #assert(V1 == 91)
}

#test
{
    func arrayInit(flag: bool)->s32
    {
        if flag
        {
            let a: IfElseArray = [2, 4, 6]
            return a[0] + a[2]
        }
        else
        {
            let a: IfElseArray = [5, 7, 9]
            return a[1] + a[2]
        }
    }

    const V0 = #run arrayInit(true)
    const V1 = #run arrayInit(false)
    #assert(V0 == 8)
    #assert(V1 == 16)
}

#test
{
    func enumInit(flag: bool)->s32
    {
        if flag
        {
            let e: IfElseKind = IfElseKind.A
            let v: s32 = cast(s32) cast(u16) e
            return v + 1
        }
        else
        {
            let e = IfElseKind.B
            let v = cast(s32) cast(u16) e
            return v + 2
        }
    }

    const V0 = #run enumInit(true)
    const V1 = #run enumInit(false)
    #assert(V0 == 3)
    #assert(V1 == 7)
}

#test
{
    func pointerInit(flag: bool)->s32
    {
        if flag
        {
            let p: *void = null
            if p == null
            {
                return 1
            }
            else
            {
                return 0
            }
        }
        else
        {
            let p: *void = cast(*void) 0x12'u64
            if p != null
            {
                return 2
            }
            else
            {
                return 0
            }
        }
    }

    const V0 = #run pointerInit(true)
    const V1 = #run pointerInit(false)
    #assert(V0 == 1)
    #assert(V1 == 2)
}

#test
{
    func seedA()->s32 { return 12 }
    func seedB(value: s32)->s32 { return value * 3 }

    func callInit(flag: bool)->s32
    {
        if flag
        {
            let x = seedA()
            let y = seedB(x + 1)
            return y
        }
        else
        {
            let x = seedB(4)
            let y = seedA() + x
            return y
        }
    }

    const V0 = #run callInit(true)
    const V1 = #run callInit(false)
    #assert(V0 == 39)
    #assert(V1 == 24)
}

#test
{
    func matrixBool(flag: bool)->bool
    {
        if flag
        {
            let v: bool = true
            return v
        }
        else
        {
            let v: bool = false
            return v
        }
    }

    func matrixS8(flag: bool)->s8
    {
        if flag
        {
            let v: s8 = -12's8
            return v
        }
        else
        {
            let v: s8 = 45's8
            return v
        }
    }

    func matrixS16(flag: bool)->s16
    {
        if flag
        {
            let v: s16 = -1234's16
            return v
        }
        else
        {
            let v: s16 = 2345's16
            return v
        }
    }

    func matrixS32(flag: bool)->s32
    {
        if flag
        {
            let v: s32 = -123456
            return v
        }
        else
        {
            let v: s32 = 654321
            return v
        }
    }

    func matrixS64(flag: bool)->s64
    {
        if flag
        {
            let v: s64 = -5000000000's64
            return v
        }
        else
        {
            let v: s64 = 7000000000's64
            return v
        }
    }

    func matrixU8(flag: bool)->u8
    {
        if flag
        {
            let v: u8 = 12'u8
            return v
        }
        else
        {
            let v: u8 = 34'u8
            return v
        }
    }

    func matrixU16(flag: bool)->u16
    {
        if flag
        {
            let v: u16 = 1234'u16
            return v
        }
        else
        {
            let v: u16 = 4321'u16
            return v
        }
    }

    func matrixU32(flag: bool)->u32
    {
        if flag
        {
            let v: u32 = 123456'u32
            return v
        }
        else
        {
            let v: u32 = 654321'u32
            return v
        }
    }

    func matrixU64(flag: bool)->u64
    {
        if flag
        {
            let v: u64 = 5000000000'u64
            return v
        }
        else
        {
            let v: u64 = 7000000000'u64
            return v
        }
    }

    func matrixF32(flag: bool)->f32
    {
        if flag
        {
            let v: f32 = 1.25'f32
            return v
        }
        else
        {
            let v: f32 = 2.5'f32
            return v
        }
    }

    func matrixF64(flag: bool)->f64
    {
        if flag
        {
            let v: f64 = 1.5'f64
            return v
        }
        else
        {
            let v: f64 = 3.25'f64
            return v
        }
    }

    func matrixRune(flag: bool)->rune
    {
        if flag
        {
            let v: rune = 'A'
            return v
        }
        else
        {
            let v: rune = 'Z'
            return v
        }
    }

    func matrixString(flag: bool)->string
    {
        if flag
        {
            let v: string = "Hi"
            return v
        }
        else
        {
            let v: string = "Yo"
            return v
        }
    }

    func matrixAlias(flag: bool)->IfElseAlias
    {
        if flag
        {
            let v: IfElseAlias = 77
            return v
        }
        else
        {
            let v: IfElseAlias = 99
            return v
        }
    }

    func matrixEnum(flag: bool)->IfElseKind
    {
        if flag
        {
            let v: IfElseKind = IfElseKind.A
            return v
        }
        else
        {
            let v: IfElseKind = IfElseKind.B
            return v
        }
    }

    func matrixStruct(flag: bool)->IfElsePoint
    {
        if flag
        {
            let v: IfElsePoint = {x: 1, y: 2}
            return v
        }
        else
        {
            let v: IfElsePoint = {x: 3, y: 4}
            return v
        }
    }

    func matrixArray(flag: bool)->IfElseArray
    {
        if flag
        {
            let v: IfElseArray = [1, 2, 3]
            return v
        }
        else
        {
            let v: IfElseArray = [4, 5, 6]
            return v
        }
    }

    func matrixPointer(flag: bool)->*void
    {
        if flag
        {
            let v: *void = null
            return v
        }
        else
        {
            let v: *void = cast(*void) 0x34'u64
            return v
        }
    }

    const B0 = #run matrixBool(true)
    const B1 = #run matrixBool(false)
    #assert(#typeof(B0) == bool)
    #assert(#typeof(B1) == bool)
    #assert(B0 == true)
    #assert(B1 == false)

    const S80 = #run matrixS8(true)
    const S81 = #run matrixS8(false)
    #assert(#typeof(S80) == s8)
    #assert(#typeof(S81) == s8)
    #assert(S80 == -12's8)
    #assert(S81 == 45's8)

    const S160 = #run matrixS16(true)
    const S161 = #run matrixS16(false)
    #assert(#typeof(S160) == s16)
    #assert(#typeof(S161) == s16)
    #assert(S160 == -1234's16)
    #assert(S161 == 2345's16)

    const S320 = #run matrixS32(true)
    const S321 = #run matrixS32(false)
    #assert(#typeof(S320) == s32)
    #assert(#typeof(S321) == s32)
    #assert(S320 == -123456)
    #assert(S321 == 654321)

    const S640 = #run matrixS64(true)
    const S641 = #run matrixS64(false)
    #assert(#typeof(S640) == s64)
    #assert(#typeof(S641) == s64)
    #assert(S640 == -5000000000's64)
    #assert(S641 == 7000000000's64)

    const U80 = #run matrixU8(true)
    const U81 = #run matrixU8(false)
    #assert(#typeof(U80) == u8)
    #assert(#typeof(U81) == u8)
    #assert(U80 == 12'u8)
    #assert(U81 == 34'u8)

    const U160 = #run matrixU16(true)
    const U161 = #run matrixU16(false)
    #assert(#typeof(U160) == u16)
    #assert(#typeof(U161) == u16)
    #assert(U160 == 1234'u16)
    #assert(U161 == 4321'u16)

    const U320 = #run matrixU32(true)
    const U321 = #run matrixU32(false)
    #assert(#typeof(U320) == u32)
    #assert(#typeof(U321) == u32)
    #assert(U320 == 123456'u32)
    #assert(U321 == 654321'u32)

    const U640 = #run matrixU64(true)
    const U641 = #run matrixU64(false)
    #assert(#typeof(U640) == u64)
    #assert(#typeof(U641) == u64)
    #assert(U640 == 5000000000'u64)
    #assert(U641 == 7000000000'u64)

    const F320 = #run matrixF32(true)
    const F321 = #run matrixF32(false)
    #assert(#typeof(F320) == f32)
    #assert(#typeof(F321) == f32)
    #assert(F320 == 1.25'f32)
    #assert(F321 == 2.5'f32)

    const F640 = #run matrixF64(true)
    const F641 = #run matrixF64(false)
    #assert(#typeof(F640) == f64)
    #assert(#typeof(F641) == f64)
    #assert(F640 == 1.5'f64)
    #assert(F641 == 3.25'f64)

    const R0 = #run matrixRune(true)
    const R1 = #run matrixRune(false)
    #assert(#typeof(R0) == rune)
    #assert(#typeof(R1) == rune)
    #assert(R0 == 'A')
    #assert(R1 == 'Z')

    const ST0 = #run matrixString(true)
    const ST1 = #run matrixString(false)
    #assert(#typeof(ST0) == string)
    #assert(#typeof(ST1) == string)
    #assert(ST0 == "Hi")
    #assert(ST1 == "Yo")

    const A0 = #run matrixAlias(true)
    const A1 = #run matrixAlias(false)
    #assert(#typeof(A0) == IfElseAlias)
    #assert(#typeof(A1) == IfElseAlias)
    #assert(cast(s32) A0 == 77)
    #assert(cast(s32) A1 == 99)

    const E0 = #run matrixEnum(true)
    const E1 = #run matrixEnum(false)
    #assert(#typeof(E0) == IfElseKind)
    #assert(#typeof(E1) == IfElseKind)
    #assert(cast(u16) E0 == 2'u16)
    #assert(cast(u16) E1 == 5'u16)

    const P0 = #run matrixStruct(true)
    const P1 = #run matrixStruct(false)
    #assert(#typeof(P0) == IfElsePoint)
    #assert(#typeof(P1) == IfElsePoint)
    #assert(P0.x == 1)
    #assert(P0.y == 2)
    #assert(P1.x == 3)
    #assert(P1.y == 4)

    const AR0 = #run matrixArray(true)
    const AR1 = #run matrixArray(false)
    #assert(#typeof(AR0) == IfElseArray)
    #assert(#typeof(AR1) == IfElseArray)
    #assert(AR0[0] == 1)
    #assert(AR0[2] == 3)
    #assert(AR1[0] == 4)
    #assert(AR1[2] == 6)

    const PTR0 = #run matrixPointer(true)
    const PTR1 = #run matrixPointer(false)
    #assert(#typeof(PTR0) == *void)
    #assert(#typeof(PTR1) == *void)
    #assert(PTR0 == null)
    #assert(PTR1 != null)
}

#test
{
    func useIfLocalOutside(flag: bool)->s32
    {
        if flag
        {
            let localInIf = 1
            return localInIf
        }
        else
        {
            return 2
        }

        return localInIf // swc-expected-error {{sema_err_unknown_symbol}}
    }

    const V0 = #run useIfLocalOutside(true)
}

#test
{
    func useElseLocalOutside(flag: bool)->s32
    {
        if flag
        {
            return 1
        }
        else
        {
            let localInElse = 2
            return localInElse
        }

        return localInElse // swc-expected-error {{sema_err_unknown_symbol}}
    }

    const V0 = #run useElseLocalOutside(false)
}

#test
{
    func ifElseNoInitVar(flag: bool)->s32
    {
        if flag
        {
            var x: s32
            return x + 1
        }
        else
        {
            var y: s32
            return y + 2
        }
    }

    const V0 = #run ifElseNoInitVar(true)
    const V1 = #run ifElseNoInitVar(false)
    #assert(V0 == 1)
    #assert(V1 == 2)
}

#test
{
    func explicitUndefinedSkipInit()->s32
    {
        var x: s32 = undefined
        return 7
    }

    const V0 = #run explicitUndefinedSkipInit()
    #assert(V0 == 7)
}
