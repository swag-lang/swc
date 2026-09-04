#global private

#test
{
    var a: typeinfo = s32
    var hit         = 0
    switch a
    {
    case s32:
        hit = 1
        break
    }
    Swag.assert(hit == 1)
}

#test
{
    var a: typeinfo = s32
    var hit         = 0
    switch a
    {
    case s32:
        hit = 1
        break
    }
    Swag.assert(hit == 1)
}

#test
{
    var a: typeinfo = f32
    var hit         = 0
    switch a
    {
    case s32:
        hit = 1
        break
    default:
        hit = 2
        break
    }
    Swag.assert(hit == 2)
}

// A comparison that folds must answer like the same comparison at run time. Type identity is
// the runtime hash, which ignores the '?' qualifier, so both sides of this pair are true.
alias NullString = string?
const TN: typeinfo = NullString
#assert(TN == string)

#test
{
    var a: typeinfo = NullString
    Swag.assert(a == string)
}

// A nullable form is the same type as the plain one, so 'case' selects it just like '=='
// does. Each qualified form owns a distinct descriptor, so matching descriptor addresses
// instead of type identity would silently fall through to 'default'.
#test
{
    var text: string?  = "value"
    var a:    typeinfo = #typeof(text)
    Swag.assert(a == string)

    var hit = 0
    switch a
    {
    case string:
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
    var ptr: *s32?
    var a:   typeinfo = #typeof(ptr)
    Swag.assert(a == *s32)

    var hit = 0
    switch a
    {
    case *s32:
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
    func switchManyTypes(v: typeinfo)->s32
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

    var first:    typeinfo = s8
    var middle:   typeinfo = u16
    var last:     typeinfo = string
    var fallback: typeinfo = *s32
    Swag.assert(switchManyTypes(first) == 1)
    Swag.assert(switchManyTypes(middle) == 6)
    Swag.assert(switchManyTypes(last) == 12)
    Swag.assert(switchManyTypes(fallback) == 99)
}

#test
{
    func switchNullableTypeInfoValue(v: typeinfo?)->s32
    {
        switch v
        {
        case s32:  return 1
        case null: return 2
        default:   return 3
        }
    }

    var present: typeinfo? = s32
    var absent:  typeinfo? = null
    Swag.assert(switchNullableTypeInfoValue(present) == 1)
    Swag.assert(switchNullableTypeInfoValue(absent) == 2)
}
