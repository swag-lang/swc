#global private

struct SwitchAnyBase
{
    value: s32 = 10
}

struct SwitchAnyDerived
{
    using base: SwitchAnyBase
    extra:      s32 = 20
}

const SwitchPointerValues = [11, 22, 33]

enum SwitchStrictAliasEnum: s32
{
    A = 1,
    B = 2
}

#[Swag.Strict]
alias StrictSwitchAliasEnum = SwitchStrictAliasEnum

#[Swag.Strict]
alias StrictSwitchS32       = s32

#[Swag.Strict]
alias StrictSwitchF32       = f32

#test
{
    var v   = 2
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
    Swag.assert(hit == 2)
}

#test
{
    func switchPointer(v: const *s32?)->s32
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

    Swag.assert(switchPointer(&SwitchPointerValues[0]) == 11)
    Swag.assert(switchPointer(&SwitchPointerValues[1]) == 23)
    Swag.assert(switchPointer(&SwitchPointerValues[2]) == 23)
    Swag.assert(switchPointer(null) == 0)
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
    Swag.assert(hit == 101)
}

#test
{
    func switchDense(v: s8)->s32
    {
        switch v
        {
        case -16: return -16
        case -15: return -15
        case -14: return -14
        case -13: return -13
        case -12: return -12
        case -11: return -11
        case -10: return -10
        case -9:  return -9
        case -8:  return -8
        case -7:  return -7
        case -6:  return -6
        case -5:  return -5
        case -4:  return -4
        case -3:  return -3
        case -2:  return -2
        case -1:  return -1
        case 0:   return 0
        case 1:   return 1
        case 2:   return 2
        case 3:   return 3
        case 4:   return 4
        case 5:   return 5
        case 6:   return 6
        case 7:   return 7
        case 8:   return 8
        case 9:   return 9
        case 10:  return 10
        case 11:  return 11
        case 12:  return 12
        case 13:  return 13
        case 14:  return 14
        case 15:  return 15
        default:  return 99
        }
    }

    var below:  s8 = -17
    var lower:  s8 = -16
    var middle: s8 = 0
    var upper:  s8 = 15
    var above:  s8 = 16
    Swag.assert(switchDense(below) == 99)
    Swag.assert(switchDense(lower) == -16)
    Swag.assert(switchDense(middle) == 0)
    Swag.assert(switchDense(upper) == 15)
    Swag.assert(switchDense(above) == 99)
}

#test
{
    enum E: s32
    {
        A = 1,
        B = 2
    }

    var v: E = E.B
    var hit  = 0
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
    Swag.assert(hit == 2)
}

#test
{
    enum E: s32
    {
        A = 1,
        B = 2
    }

    const expected = E.A
    var value: E = .A
    var hit      = false
    switch value
    {
    case expected:
        hit = true
    case .B:
        break
    }
    Swag.assert(hit)
}

#test
{
    var v   = cast(StrictSwitchAliasEnum) SwitchStrictAliasEnum.B
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
    Swag.assert(hit == 2)
}

#test
{
    enum E: s32
    {
        A = 1,
        B = 2,
        C = 3
    }

    var v: E = .A
    Swag.assert(v == .A)
}

#test
{
    enum E: s32
    {
        A = 1,
        B = 2
    }

    var v: E = E.B
    var hit  = 0
    switch v
    {
    case E.A:
        hit = 1
        break
    default:
        hit = 2
        break
    }
    Swag.assert(hit == 2)
}

#test
{
    alias MyInt = s32
    var v: MyInt = 3
    var hit      = 0
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
    Swag.assert(hit == 3)
}

#test
{
    var v   = cast(StrictSwitchS32) 3
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
    Swag.assert(hit == 3)
}

#test
{
    var v   = cast(StrictSwitchF32) 1.5
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
    Swag.assert(hit == 1)
}

#test
{
    var v   = 1.5
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
    Swag.assert(hit == 1)
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

    Swag.assert(hit == 3)
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

    Swag.assert(group == 1)
    Swag.assert(score == 1)
    Swag.assert(count == 0)
}

#test
{
    var v   = true
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
    Swag.assert(hit == 1)
}

#test
{
    var v   = "hello"
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
    Swag.assert(hit == 1)
}

// A switch over strings compares them where it stands rather than calling out per case, so the
// comparison has to answer for every length, for bytes above 0x7F, and for names that differ only
// at one end.
func switchStringName(value: string)->s32
{
    switch value
    {
    case "":                  return 1
    case "a":                 return 2
    case "b":                 return 3
    case "ab":                return 4
    case "ba":                return 5
    case "abc":               return 6
    case "abd":               return 7
    case "xbc":               return 8
    case "abcd":              return 9
    case "abce":              return 10
    case "abcde":             return 11
    case "abcdf":             return 12
    case "xbcde":             return 13
    case "abcdefg":           return 14
    case "abcdefh":           return 15
    case "abcdefgh":          return 16
    case "abcdefgi":          return 17
    case "abcdefghi":         return 18
    case "abcdefghj":         return 19
    case "bbcdefghi":         return 20
    case "abcdefghijklmnop":  return 21
    case "abcdefghijklmnoq":  return 22
    case "abcdefghijklmnopq": return 23
    case "abcdefghijklmnopr": return 24
    case "caf\xC3\xA9":       return 25
    case "caf\xC3\xB4":       return 26
    case "\xFF\xFE":          return 27
    case "\xFF\xFF":          return 28
    }

    return 0
}

// Copies a literal into a buffer and hands back a string over it, so the switch sees a value it
// cannot fold away.
func switchStringAtRuntime(buffer: [*] u8, text: string)->string
{
    for index in text.count do
        buffer[index] = text[index]
    return Swag.makeString(buffer, text.count)
}

#test
{
    var buffer: [64] u8

    let expected: [28] string = [
        "", "a", "b", "ab", "ba", "abc", "abd", "xbc", "abcd", "abce",
        "abcde", "abcdf", "xbcde", "abcdefg", "abcdefh", "abcdefgh", "abcdefgi",
        "abcdefghi", "abcdefghj", "bbcdefghi", "abcdefghijklmnop", "abcdefghijklmnoq",
        "abcdefghijklmnopq", "abcdefghijklmnopr", "caf\xC3\xA9", "caf\xC3\xB4",
        "\xFF\xFE", "\xFF\xFF"]

    for text, index in expected
    {
        let value = switchStringAtRuntime(&buffer[0], text)
        Swag.assert(switchStringName(value) == cast(s32) index + 1)
    }

    // Nothing else matches, including the prefixes and suffixes of what does.
    let others: [6] string = ["c", "abcdefghijklmno", "abcdefghijklmnops", "abcdefg ", " abcdefg", "caf"]
    for text in others
    {
        let value = switchStringAtRuntime(&buffer[0], text)
        Swag.assert(!switchStringName(value))
    }
}

// A `where` on a string case still falls through to the tests written after it.
func switchStringWhere(value: string, allow: bool)->s32
{
    switch value
    {
    case "keep" where allow: return 1
    case "keep":             return 2
    case "drop":             return 3
    }

    return 0
}

#test
{
    var buffer: [16] u8
    let kept = switchStringAtRuntime(&buffer[0], "keep")
    Swag.assert(switchStringWhere(kept, true) == 1)
    Swag.assert(switchStringWhere(kept, false) == 2)

    var other: [16] u8
    let dropped = switchStringAtRuntime(&other[0], "drop")
    Swag.assert(switchStringWhere(dropped, true) == 3)
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
    var hit  = 0
    switch mode
    {
    case .Screen0 to .Screen3:
        hit = 1
        break
    default:
        hit = 2
        break
    }
    Swag.assert(hit == 1)

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
    Swag.assert(hit == 4)
}

#test
{
    var v   = 2
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
    Swag.assert(hit == 1)
}

#test
{
    var v   = 2
    var hit = 0
    switch #complete v
    {
    case 1 to 3:
        hit = 1
        break
    }
    Swag.assert(hit == 1)
}

func toto()->s32 => 1
#test
{
    var hit = 0
    switch #complete toto()
    {
    case 1 to 3:
        hit = 1
        break
    }
    Swag.assert(hit == 1)
}

#test
{
    var a   = 2
    var b   = 1
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
    Swag.assert(hit == 0)
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
    Swag.assert(switchAnyUsingBase(a) == 1)
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
    Swag.assert(switchAnyUsingBaseBinding(a) == 7)
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
    Swag.assert(switchAnyStringBinding(a))
}
