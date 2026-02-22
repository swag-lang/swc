#global internal

struct IfElsePoint
{
    x: s32
    y: s32
}

alias IfElseArray = [3] s32

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
