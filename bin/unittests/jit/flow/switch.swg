#global private

enum RunSwitchEnum: s32
{
    A = 1
    B = 2
}

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

#test
{
    func switchScalar(v: s32)->s32
    {
        switch v
        {
        case 1:
            return 11
        case 2, 3:
            return 23
        default:
            return 90
        }
    }

    const V0 = #run switchScalar(1)
    const V1 = #run switchScalar(2)
    const V2 = #run switchScalar(3)
    const V3 = #run switchScalar(9)
    #assert(V0 == 11)
    #assert(V1 == 23)
    #assert(V2 == 23)
    #assert(V3 == 90)
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

    const V0 = #run switchPointer(&SwitchPointerValues[0])
    const V1 = #run switchPointer(&SwitchPointerValues[1])
    const V2 = #run switchPointer(&SwitchPointerValues[2])
    const V3 = #run switchPointer(null)
    #assert(V0 == 11)
    #assert(V1 == 23)
    #assert(V2 == 23)
    #assert(V3 == 0)
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

    #assert(#run switchDense(-17) == 99)
    #assert(#run switchDense(-16) == -16)
    #assert(#run switchDense(0) == 0)
    #assert(#run switchDense(15) == 15)
    #assert(#run switchDense(16) == 99)
}

#test
{
    func switchFloat(v: f64)->s32
    {
        switch v
        {
        case 1.25:
            return 12
        case 2.5:
            return 25
        default:
            return 0
        }
    }

    const V0 = #run switchFloat(1.25'f64)
    const V1 = #run switchFloat(2.5'f64)
    const V2 = #run switchFloat(8.0'f64)
    #assert(V0 == 12)
    #assert(V1 == 25)
    #assert(V2 == 0)
}

#test
{
    func switchRange(v: s32)->s32
    {
        switch v
        {
        case 1 to 3:
            return 10
        case 4 until 7:
            return 20
        default:
            return 30
        }
    }

    const V0 = #run switchRange(1)
    const V1 = #run switchRange(3)
    const V2 = #run switchRange(4)
    const V3 = #run switchRange(6)
    const V4 = #run switchRange(7)
    #assert(V0 == 10)
    #assert(V1 == 10)
    #assert(V2 == 20)
    #assert(V3 == 20)
    #assert(V4 == 30)
}

#test
{
    func switchWhere(v: s32, takeFirst: bool)->s32
    {
        switch v
        {
        case 1 where takeFirst:
            return 100
        case 1:
            return 200
        default:
            return 300
        }
    }

    const V0 = #run switchWhere(1, true)
    const V1 = #run switchWhere(1, false)
    const V2 = #run switchWhere(2, true)
    #assert(V0 == 100)
    #assert(V1 == 200)
    #assert(V2 == 300)
}

#test
{
    func switchTypeInfo(v: typeinfo)->s32
    {
        switch v
        {
        case s8:     return 1
        case s16:    return 2
        case s32:    return 3
        case s64:    return 4
        case u8:     return 5
        case u16:    return 6
        case u32:    return 7
        case u64:    return 8
        case f32:    return 9
        case f64:    return 10
        case bool:   return 11
        case string: return 12
        default:     return 99
        }
    }

    const T0: typeinfo = s8
    const T1: typeinfo = s32
    const T2: typeinfo = u64
    const T3: typeinfo = bool
    const T4: typeinfo = *s32
    const V0           = #run switchTypeInfo(T0)
    const V1           = #run switchTypeInfo(T1)
    const V2           = #run switchTypeInfo(T2)
    const V3           = #run switchTypeInfo(T3)
    const V4           = #run switchTypeInfo(T4)
    #assert(V0 == 1)
    #assert(V1 == 3)
    #assert(V2 == 8)
    #assert(V3 == 11)
    #assert(V4 == 99)
}

#test
{
    func switchNullableTypeInfoValue(v: #null typeinfo)->s32
    {
        switch v
        {
        case s32:  return 1
        case null: return 2
        default:   return 3
        }
    }

    const T0: #null typeinfo = s32
    const T1: #null typeinfo = null
    #assert(#run switchNullableTypeInfoValue(T0) == 1)
    #assert(#run switchNullableTypeInfoValue(T1) == 2)
}

// A nullable form is the same type as the plain one, so 'case' selects it just like '=='
// does. Each qualified form owns a distinct descriptor, so matching descriptor addresses
// instead of type identity would silently fall through to 'default'.
#test
{
    alias NullString = #null string

    func switchNullableTypeInfo(v: typeinfo)->s32
    {
        switch v
        {
        case string:
            return 1
        default:
            return 2
        }
    }

    const TN: typeinfo = NullString
    const VN           = #run switchNullableTypeInfo(TN)
    #assert(VN == 1)
}

#test
{
    func switchNoExpr(a: s32, b: s32)->s32
    {
        switch
        {
        case a > b:
            return 10
        case a == b:
            return 20
        default:
            return 30
        }
    }

    const V0 = #run switchNoExpr(5, 1)
    const V1 = #run switchNoExpr(3, 3)
    const V2 = #run switchNoExpr(1, 4)
    #assert(V0 == 10)
    #assert(V1 == 20)
    #assert(V2 == 30)
}

#test
{
    func switchFallthrough(v: s32)->s32
    {
        var r = 0
        switch v
        {
        case 1:
            r = r + 1
            fallthrough
        case 2:
            r = r + 2
            break
        default:
            r = 10
        }

        return r
    }

    const V0 = #run switchFallthrough(1)
    const V1 = #run switchFallthrough(2)
    const V2 = #run switchFallthrough(5)
    #assert(V0 == 3)
    #assert(V1 == 2)
    #assert(V2 == 10)
}

#test
{
    func switchEnum(v: RunSwitchEnum)->s32
    {
        switch v
        {
        case .A:
            return 7
        case .B:
            return 9
        }
    }

    const V0 = #run switchEnum(.A)
    const V1 = #run switchEnum(.B)
    #assert(V0 == 7)
    #assert(V1 == 9)
}

#test
{
    func switchDefaultWhere(v: s32, flag: bool)->s32
    {
        switch v
        {
        case 1:
            return 10
        default where flag:
            return 20
        default:
            return 30
        }
    }

    const V0 = #run switchDefaultWhere(1, true)
    const V1 = #run switchDefaultWhere(2, true)
    const V2 = #run switchDefaultWhere(2, false)
    const V3 = #run switchDefaultWhere(5, false)
    #assert(V0 == 10)
    #assert(V1 == 20)
    #assert(V2 == 30)
    #assert(V3 == 30)
}

#test
{
    func switchMultipleDefaultWhere(v: s32, a: bool, b: bool)->s32
    {
        switch v
        {
        case 1:
            return 10
        default where a:
            return 20
        default where b:
            return 30
        default:
            return 40
        }
    }

    const V0 = #run switchMultipleDefaultWhere(2, true, true)
    const V1 = #run switchMultipleDefaultWhere(2, false, true)
    const V2 = #run switchMultipleDefaultWhere(2, false, false)
    #assert(V0 == 20)
    #assert(V1 == 30)
    #assert(V2 == 40)
}

#test
{
    func switchAnyString(x: any)->s32
    {
        switch x
        {
        case string:
            return 1
        case s32:
            return 2
        default:
            return 0
        }
    }

    var a: any = "hello"
    Swag.assert(switchAnyString(a) == 1)
    a = 42
    Swag.assert(switchAnyString(a) == 2)
    a = true
    Swag.assert(switchAnyString(a) == 0)
}

#test
{
    func switchAnyMultiType(x: any)->s32
    {
        switch x
        {
        case bool:
            return 10
        case f64:
            return 20
        case s32:
            return 30
        default:
            return 0
        }
    }

    var a: any = true
    Swag.assert(switchAnyMultiType(a) == 10)
    a = 3.14
    Swag.assert(switchAnyMultiType(a) == 20)
    a = 99
    Swag.assert(switchAnyMultiType(a) == 30)
    a = "fallback"
    Swag.assert(switchAnyMultiType(a) == 0)
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

#test
{
    func switchCaseMustBeConst(v: s32)->s32
    {
        switch v
        {
        case v:     // swc-expected-error {{sema_err_switch_case_not_const}}
            return 1
        default:
            return 0
        }
    }
}

// 'switch #complete' requires every declared enum value to have a case, and no 'default'.
#test
{
    enum SwitchCompleteKind
    {
        First
        Second
        Third
    }

    func nameOf(kind: SwitchCompleteKind)->string
    {
        switch #complete kind
        {
        case SwitchCompleteKind.First:  return "first"
        case SwitchCompleteKind.Second: return "second"
        case SwitchCompleteKind.Third:  return "third"
        }

        unreachable
    }

    Swag.assert(nameOf(SwitchCompleteKind.First) == "first")
    Swag.assert(nameOf(SwitchCompleteKind.Second) == "second")
    Swag.assert(nameOf(SwitchCompleteKind.Third) == "third")
}
