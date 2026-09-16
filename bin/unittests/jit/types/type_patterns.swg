#global private

interface IPatternValue { mtd value()->s32 }
interface IPatternOther { mtd other()->s32 }

#[Swag.DynCast]
struct PatternBase { number: s32 = 42 }

struct PatternValue
{
    prefix:     u64 = 99
    using base: PatternBase
}

struct PatternOther {}

impl IPatternValue for PatternValue
{
    mtd value()->s32 => .number
}

impl IPatternOther for PatternValue
{
    mtd other()->s32 => .number + 1
}

func(T) patternRead(value: *T)->s32
    where T is IPatternValue
{
    let view: IPatternValue = value
    return view.value()
}

func patternSource(value: IPatternValue, calls: *s32)->IPatternValue
{
    calls[] += 1
    return value
}

#test
{
    #assert(PatternValue is IPatternValue)
    #assert(IPatternValue is IPatternValue)
    #assert(not (PatternOther is IPatternValue))
    #assert(s32 is s32)
    #assert(not (s32 is s64))
    var value: PatternValue
    Swag.assert(patternRead(&value) == 42)
    let view: IPatternValue = &value
    Swag.assert(view is PatternValue)
    Swag.assert(not (view is PatternOther))
    Swag.assert(view is PatternValue and view is IPatternOther)
    Swag.assert(view is PatternOther or view is PatternValue)
    Swag.assert((view is PatternValue) == true)
    if view is IPatternOther as other do
        Swag.assert(other.other() == 43)
    else do
        Swag.assert(false)
}

#test
{
    var value: PatternValue
    let view:  IPatternValue = &value
    var calls  = 0
    var result = 0
    if patternSource(view, &calls) is PatternValue as item where item.number < 0 do
        result = -1
    elif patternSource(view, &calls) is PatternOther as item do
        result = -2
    elif patternSource(view, &calls) is PatternValue as item where item.number == 42
    {
        #assert(#typeof(item) == #type *PatternValue)
        Swag.assert(item == &value)
        result = item.number
    }
    else do
        result = -3
    Swag.assert(calls == 3 and result == 42)
}

#test
{
    var value: PatternValue
    let view:  IPatternValue = &value
    var calls  = 0
    var result = 0
    switch patternSource(view, &calls)
    {
    case PatternOther where calls > 0: result = -1
    case PatternValue as item where item.number < 0: result = -2
    case PatternValue as item where item.number == 42:
        #assert(#typeof(item) == #type *PatternValue)
        Swag.assert(item == &value)
        result = item.number
        fallthrough
    case PatternOther as item: result = -3
    case PatternValue as item where item.number > 50: result = -4
    case PatternValue as item: result += item.number
    default: result = -5
    }
    Swag.assert(calls == 1 and result == 84)
    switch view
    {
    case IPatternOther as other: Swag.assert(other.other() == 43)
    default: Swag.assert(false)
    }
}

#test
{
    var value: PatternValue
    let base:  *PatternBase = &value
    Swag.assert(base is PatternValue)
    Swag.assert(not (base is PatternOther))
    if base is PatternValue as item do
        Swag.assert(item == &value)
    else do
        Swag.assert(false)
    switch base
    {
    case PatternOther:         Swag.assert(false)
    case PatternValue as item: Swag.assert(item == &value)
    default: Swag.assert(false)
    }
    let readOnly: const *PatternBase = base
    if readOnly is PatternValue as item
    {
        #assert(#typeof(item) == #type const *PatternValue)
        Swag.assert(item.number == 42)
    }
    else do
        Swag.assert(false)
    switch readOnly
    {
    case PatternValue as item:
        #assert(#typeof(item) == #type const *PatternValue)
        Swag.assert(item.number == 42)
    default: Swag.assert(false)
    }
}

func patternAbsent(value: any?)->bool
{
    if value is s32 as number do
        return true
    switch value
    {
    case s32: return true
    default:  return false
    }
}

#test
{
    var storage: s32 = 42
    let boxed:   any = &storage
    Swag.assert(boxed is s32)
    Swag.assert(not (boxed is s64))
    if boxed is s32 as number
    {
        #assert(#typeof(number) == #type *s32)
        number[] += 1
    }
    switch boxed
    {
    case s32 as number: Swag.assert(number[] == 43)
    default: Swag.assert(false)
    }
    Swag.assert(not patternAbsent(null))
    let missing: IPatternValue? = null
    Swag.assert(not (missing is PatternValue))
    switch missing
    {
    case PatternValue: Swag.assert(false)
    default: break
    }
    let noBase: *PatternBase? = null
    Swag.assert(not (noBase is PatternValue))
    switch noBase
    {
    case PatternValue as item: Swag.assert(false)
    default: break
    }
}

func patternType(source: typeinfo)->bool => source is IPatternValue

#test
{
    Swag.assert(patternType(PatternValue))
    Swag.assert(not patternType(PatternOther))
    let metadata: typeinfo = PatternValue
    if metadata is Swag.TypeInfoStruct as info do
        Swag.assert(info.fields.count != 0)
    else do
        Swag.assert(false)
}

func(T) patternOverload(value: T)->s32 where T is IPatternValue and T is IPatternOther => 1
func(T) patternOverload(value: T)->s32 where not (T is IPatternValue) => 2

#test
{
    var value: PatternValue
    Swag.assert(patternOverload(value) == 1)
    Swag.assert(patternOverload(42) == 2)
    var calls = 0
    Swag.assert(patternSource(&value, &calls) is PatternValue)
    Swag.assert(calls == 1)
    let boxed: any = &value
    switch boxed
    {
    case PatternOther, s64: Swag.assert(false)
    case PatternValue:      break
    default: Swag.assert(false)
    }
}

#test
{
    // An interface can expose static methods without an object. Presence follows
    // its table, as it does for the equivalent '#try' interface conversion.
    let view = Swag.makeInterface(null, PatternValue, IPatternValue)
    Swag.assert(view is IPatternOther)
    Swag.assert(not (view is PatternValue))
    switch view
    {
    case PatternValue: Swag.assert(false)
    case IPatternOther as other: Swag.assert(other != null)
    default: Swag.assert(false)
    }
}

func patternPointerMatch(value: *PatternBase?)->s32
{
    switch value
    {
    case null: return 0
    case PatternValue as item: return item.number
    default:   return -1
    }
}

func patternPointerOnly(value: *PatternBase?)->bool
{
    switch value
    {
    case null: return true
    default:   return false
    }
}

#test
{
    var value: PatternValue
    Swag.assert(patternPointerMatch(null) == 0)
    Swag.assert(patternPointerMatch(&value) == 42)
    Swag.assert(patternPointerOnly(null))
    Swag.assert(not patternPointerOnly(&value))
    let empty: *PatternBase? = null
    switch empty
    {
    case PatternValue: Swag.assert(false)
    case null:         break
    default:           Swag.assert(false)
    }
    let base: *PatternBase = &value
    switch base
    {
    case null, PatternValue: break
    default: Swag.assert(false)
    }
    switch base
    {
    case PatternOther, null: Swag.assert(false)
    case PatternValue:       break
    default: Swag.assert(false)
    }
}

func(T) patternGenericSwitch(value: IPatternValue, unused: *T)->s32
    where T is IPatternValue
{
    switch #complete value
    {
    case T as item: return item.number
    }
    return 0
}

#test
{
    var value: PatternValue
    Swag.assert(patternGenericSwitch(&value, &value) == 42)
}
