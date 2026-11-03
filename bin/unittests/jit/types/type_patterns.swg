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
    Swag.require(patternRead(&value) == 42)
    let view: IPatternValue = &value
    Swag.require(view is PatternValue)
    Swag.require(not (view is PatternOther))
    Swag.require(view is PatternValue and view is IPatternOther)
    Swag.require(view is PatternOther or view is PatternValue)
    Swag.require((view is PatternValue) == true)
    if view is IPatternOther as other do
        Swag.require(other.other() == 43)
    else do
        Swag.require(false)
}

#test
{
    var value: PatternValue
    let view:  IPatternValue = &value
    var calls  = 0
    var result = 0
    if patternSource(view, &calls) is PatternValue as item where item.number < 0 do
        result = -1
    elif patternSource(view, &calls) is PatternOther do
        result = -2
    elif patternSource(view, &calls) is PatternValue as item where item.number == 42
    {
        #assert(#typeof(item) == #type *PatternValue)
        Swag.require(item == &value)
        result = item.number
    }
    else do
        result = -3
    Swag.require(calls == 3 and result == 42)
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
        Swag.require(item == &value)
        result = item.number
        fallthrough
    case PatternOther:         result = -3
    case PatternValue as item where item.number > 50: result = -4
    case PatternValue as item: result += item.number
    default: result = -5
    }
    Swag.require(calls == 1 and result == 84)
    switch view
    {
    case IPatternOther as other: Swag.require(other.other() == 43)
    default: Swag.require(false)
    }
}

#test
{
    var value: PatternValue
    let base:  *PatternBase = &value
    Swag.require(base is PatternValue)
    Swag.require(not (base is PatternOther))
    if base is PatternValue as item do
        Swag.require(item == &value)
    else do
        Swag.require(false)
    switch base
    {
    case PatternOther:         Swag.require(false)
    case PatternValue as item: Swag.require(item == &value)
    default: Swag.require(false)
    }
    let readOnly: const *PatternBase = base
    if readOnly is PatternValue as item
    {
        #assert(#typeof(item) == #type const *PatternValue)
        Swag.require(item.number == 42)
    }
    else do
        Swag.require(false)
    switch readOnly
    {
    case PatternValue as item:
        #assert(#typeof(item) == #type const *PatternValue)
        Swag.require(item.number == 42)
    default: Swag.require(false)
    }
}

func patternAbsent(value: any?)->bool
{
    if value is s32 do
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
    Swag.require(boxed is s32)
    Swag.require(not (boxed is s64))
    if boxed is s32 as number
    {
        #assert(#typeof(number) == #type *s32)
        number[] += 1
    }
    switch boxed
    {
    case s32 as number: Swag.require(number[] == 43)
    default: Swag.require(false)
    }
    Swag.require(not patternAbsent(null))
    let missing: IPatternValue? = null
    Swag.require(not (missing is PatternValue))
    switch missing
    {
    case PatternValue: Swag.require(false)
    default: break
    }
    let noBase: *PatternBase? = null
    Swag.require(not (noBase is PatternValue))
    switch noBase
    {
    case PatternValue: Swag.require(false)
    default: break
    }
}

func patternType(source: typeinfo)->bool => source is IPatternValue

#test
{
    Swag.require(patternType(PatternValue))
    Swag.require(not patternType(PatternOther))
    let metadata: typeinfo = PatternValue
    if metadata is Swag.TypeInfoStruct as info do
        Swag.require(info.fields.count != 0)
    else do
        Swag.require(false)
}

func(T) patternOverload(value: T)->s32 where T is IPatternValue and T is IPatternOther => 1
func(T) patternOverload(value: T)->s32 where not (T is IPatternValue) => 2

#test
{
    var value: PatternValue
    Swag.require(patternOverload(value) == 1)
    Swag.require(patternOverload(42) == 2)
    var calls = 0
    Swag.require(patternSource(&value, &calls) is PatternValue)
    Swag.require(calls == 1)
    let boxed: any = &value
    switch boxed
    {
    case PatternOther, s64: Swag.require(false)
    case PatternValue:      break
    default: Swag.require(false)
    }
}

#test
{
    // An interface can expose static methods without an object. Presence follows
    // its table, as it does for the equivalent 'catch cast' interface conversion.
    let view = Swag.makeInterface(null, PatternValue, IPatternValue)
    Swag.require(view is IPatternOther)
    Swag.require(not (view is PatternValue))
    switch view
    {
    case PatternValue: Swag.require(false)
    case IPatternOther as other: Swag.require(other != null)
    default: Swag.require(false)
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
    Swag.require(patternPointerMatch(null) == 0)
    Swag.require(patternPointerMatch(&value) == 42)
    Swag.require(patternPointerOnly(null))
    Swag.require(not patternPointerOnly(&value))
    let empty: *PatternBase? = null
    switch empty
    {
    case PatternValue: Swag.require(false)
    case null:         break
    default:           Swag.require(false)
    }
    let base: *PatternBase = &value
    switch base
    {
    case null, PatternValue: break
    default: Swag.require(false)
    }
    switch base
    {
    case PatternOther, null: Swag.require(false)
    case PatternValue:       break
    default: Swag.require(false)
    }
}

func(T) patternGenericSwitch(value: IPatternValue, unused: *T)->s32
    where T is IPatternValue
{
    switch #complete value
    {
    case T as item: return item.number
    }
}

#test
{
    var value: PatternValue
    Swag.require(patternGenericSwitch(&value, &value) == 42)
}
