#global private

struct SwitchAnyBase
{
    value: s32 = 10
}

struct SwitchAnyDerived
{
    using base: SwitchAnyBase
    extra: s32 = 20
}

const SwitchPointerValues = [11, 22, 33]

enum SwitchStrictAliasEnum : s32
{
    A = 1,
    B = 2,
}

#[Swag.Strict]
alias StrictSwitchAliasEnum = SwitchStrictAliasEnum

#[Swag.Strict]
alias StrictSwitchS32 = s32

#[Swag.Strict]
alias StrictSwitchF32 = f32

#test
{
    var v = 2
    var hit = 0
    switch v
    {
        case 1:
            hit = 1
            break
        case 2, 3:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

#test
{
    func switchPointer(v: #null const *s32)->s32
    {
        switch v
        {
            case &SwitchPointerValues[0]:
                return 11
            case &SwitchPointerValues[1], &SwitchPointerValues[2]:
                return 23
            case null:
                return 0
            default:
                return 90
        }
    }

    @assert(switchPointer(&SwitchPointerValues[0]) == 11)
    @assert(switchPointer(&SwitchPointerValues[1]) == 23)
    @assert(switchPointer(&SwitchPointerValues[2]) == 23)
    @assert(switchPointer(null) == 0)
}

#test
{
    var hit = 0
    switch 1
    {
        case 1:
            hit += 1
            break
        default:
            hit += 10
            break
    }

    switch 1
    {
        case 1:
            hit += 100
            break
        default:
            hit += 1000
            break
    }
    @assert(hit == 101)
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
    }

    var v : E = E.B
    var hit = 0
    switch v
    {
        case E.A:
            hit = 1
            break
        case .B:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

#test
{
    var v = cast(StrictSwitchAliasEnum) SwitchStrictAliasEnum.B
    var hit = 0
    switch v
    {
        case .A:
            hit = 1
            break
        case .B:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
        C = 3,
    }

    var v : E = .A
    @assert(v == .A)
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
    }

    var v : E = E.B
    var hit = 0
    switch v
    {
        case E.A:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 2)
}

#test
{
    alias MyInt = s32
    var v : MyInt = 3
    var hit = 0
    switch v
    {
        case 1:
            hit = 1
            break
        case 3:
            hit = 3
            break
        default:
            hit = 9
            break
    }
    @assert(hit == 3)
}

#test
{
    var v = cast(StrictSwitchS32) 3
    var hit = 0
    switch v
    {
        case cast(StrictSwitchS32) 1:
            hit = 1
            break
        case cast(StrictSwitchS32) 3:
            hit = 3
            break
        default:
            hit = 9
            break
    }
    @assert(hit == 3)
}

#test
{
    var v = cast(StrictSwitchF32) 1.5
    var hit = 0
    switch v
    {
        case cast(StrictSwitchF32) 1.5:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = 1.5
    var hit = 0
    switch v
    {
        case 1.5:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var hit = 0
    switch 1
    {
        case 1: hit += 1; hit += 2
        default:
            hit = -1
            break
    }

    @assert(hit == 3)
}

#test
{
    var c = '{'
    var garbage, group, score, count = 0
    switch
    {
        case c == '!' and garbage:
            count += 10
        case c == '>' and garbage:
            garbage -= 1
        case c == '<' and !garbage:
            garbage += 1
        case c == '{' and !garbage:
            group += 1; score += group
        case c == '}' and !garbage:
            group -= 1
        case garbage:
            count += 1
        default:
            count = -1
            break
    }

    @assert(group == 1)
    @assert(score == 1)
    @assert(count == 0)
}

#test
{
    var v = true
    var hit = 0
    switch v
    {
        case true:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = "hello"
    var hit = 0
    switch v
    {
        case "hello", "world":
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

enum SwitchEnumRangeMode
{
    None
    Screen0
    Screen1
    Screen2
    Screen3
    Other
}

#test
{
    var mode = SwitchEnumRangeMode.Screen2
    var hit = 0
    switch mode
    {
        case .Screen0 to .Screen3:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)

    mode = .Other
    switch mode
    {
        case .Screen0 to .Screen3:
            hit = 3
            break
        default:
            hit = 4
            break
    }
    @assert(hit == 4)
}

#test
{
    var v = 2
    var hit = 0
    switch v
    {
        case 1 to 3:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = 2
    var hit = 0
    #[Swag.Complete]
    switch v
    {
        case 1 to 3:
            hit = 1
            break
    }
    @assert(hit == 1)
}

func toto()->s32 => 1
#test
{
    var hit = 0
    #[Swag.Complete]
    switch toto()
    {
        case 1 to 3:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var a = 2
    var b = 1
    var hit = 0
    switch a
    {
    case 1 where b == 1:
        hit = 1
        break
    case 1 where b == 2:
        hit = 2
        break
    case 1:
        hit = 3
        break
    }
    @assert(hit == 0)
}

#test
{
    func switchAnyUsingBase(x: any)->s32
    {
        switch x
        {
            case SwitchAnyBase:
                return 1
            case s32:
                return 2
            default:
                return 0
        }
    }

    var a: any = SwitchAnyDerived{base: {value: 7}, extra: 11}
    @assert(switchAnyUsingBase(a) == 1)
}

#test
{
    func switchAnyUsingBaseBinding(x: any)->s32
    {
        switch x
        {
            case SwitchAnyBase as ptr:
                return ptr.value
            default:
                return 0
        }
    }

    var a: any = SwitchAnyDerived{base: {value: 7}, extra: 11}
    @assert(switchAnyUsingBaseBinding(a) == 7)
}

#test
{
    func switchAnyStringBinding(x: any)->bool
    {
        switch x
        {
            case string as str:
                return str == "value"
            default:
                return false
        }
    }

    var a: any = "value"
    @assert(switchAnyStringBinding(a))
}
