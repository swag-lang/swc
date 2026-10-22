#global private

interface ICastValue
{
    mtd value()->s32
}

interface ICastLabel
{
    mtd label()->string
}

struct CastValue
{
    number: s32 = 42
}

struct OtherCastValue {}

impl ICastValue for CastValue
{
    mtd value()->s32 => .number
}

impl ICastLabel for CastValue
{
    mtd label()->string => "value"
}

func(T) readCastValue(value: *T)->s32
    where T is ICastValue
{
    let view = cast(ICastValue, value)
    return view.value()
}

#test
{
    var value: CastValue
    let itf      = cast(ICastValue, &value)
    let concrete = catch cast(*CastValue?, itf) else null
    Swag.assert(concrete == &value)
    let castResult1 = catch cast(*OtherCastValue?, itf) else null
    Swag.assert(castResult1 == null)
    Swag.assert(assume cast (*CastValue, itf) == &value)
    let label = catch cast(ICastLabel?, itf) else null
    if label != null do
        Swag.assert(label.label() == "value")
    Swag.assert(label != null)
    let directLabel: ICastLabel = &value
    Swag.assert(label == directLabel)
    Swag.assert(readCastValue(&value) == 42)
}

#test
{
    var value: CastValue
    var boxed: any = &value
    Swag.assert((catch cast(*CastValue?, boxed) else null) == &value)
    let castResult2 = catch cast(*OtherCastValue?, boxed) else null
    Swag.assert(castResult2 == null)
    let view = catch cast(ICastValue?, boxed) else null
    if view != null do
        Swag.assert(view.value() == 42)
    Swag.assert(view != null)
}

#test
{
    var boxed: any = 17's32
    let value      = catch cast(*s32?, boxed) else null
    if value != null do
        Swag.assert(value[] == 17)
    Swag.assert(value != null)
    let castResult3 = catch cast(*s64?, boxed) else null
    Swag.assert(castResult3 == null)
    Swag.assert(assume cast (s32, boxed) == 17)
}

#assert(CastValue is ICastValue)
#assert(not (OtherCastValue is ICastValue))
#assert(not (s32 is ICastValue))

#test
{
    var value:    CastValue
    let readOnly: const *CastValue = &value
    let boxed:    const any        = readOnly
    Swag.assert((catch cast(const *CastValue?, boxed) else null) == readOnly)
    let absent: *CastValue? = null
    let castResult4         = cast(*CastValue?, absent)
    Swag.assert(castResult4 == null)
}

#test
{
    var value: CastValue
    let itf        = cast(ICastValue, &value)
    let boxed: any = itf
    Swag.assert((catch cast(*CastValue?, boxed) else null) == &value)
    let label = catch cast(ICastLabel?, boxed) else null
    Swag.assert(label != null)
    Swag.assert(label.label() == "value")
}

#test
{
    let source = Swag.makeInterface(null, CastValue, ICastValue)
    let target = catch cast(ICastLabel?, source) else null
    Swag.assert(target != null)
    Swag.assert(target.label() == "value")
    let castResult5 = catch cast(*CastValue?, source) else null
    Swag.assert(castResult5 == null)
    let absent: *CastValue? = null
    let castResult6         = cast(ICastLabel?, absent)
    Swag.assert(castResult6 == null)
}
