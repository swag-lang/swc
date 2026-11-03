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
    let concrete = catch cast(*CastValue?, itf)
    Swag.require(concrete == &value)
    let castResult1 = catch cast(*OtherCastValue?, itf)
    Swag.require(castResult1 == null)
    Swag.require(assume cast (*CastValue, itf) == &value)
    let label = catch cast(ICastLabel?, itf)
    if label != null do
        Swag.require(label.label() == "value")
    Swag.require(label != null)
    let directLabel: ICastLabel = &value
    Swag.require(label == directLabel)
    Swag.require(readCastValue(&value) == 42)
}

#test
{
    var value: CastValue
    var boxed: any = &value
    Swag.require((catch cast(*CastValue?, boxed)) == &value)
    let castResult2 = catch cast(*OtherCastValue?, boxed)
    Swag.require(castResult2 == null)
    let view = catch cast(ICastValue?, boxed)
    if view != null do
        Swag.require(view.value() == 42)
    Swag.require(view != null)
}

#test
{
    var boxed: any = 17's32
    let value      = catch cast(*s32?, boxed)
    if value != null do
        Swag.require(value[] == 17)
    Swag.require(value != null)
    let castResult3 = catch cast(*s64?, boxed)
    Swag.require(castResult3 == null)
    Swag.require(assume cast (s32, boxed) == 17)
}

#assert(CastValue is ICastValue)
#assert(not (OtherCastValue is ICastValue))
#assert(not (s32 is ICastValue))

#test
{
    var value:    CastValue
    let readOnly: const *CastValue = &value
    let boxed:    const any        = readOnly
    Swag.require((catch cast(const *CastValue?, boxed)) == readOnly)
    let absent: *CastValue? = null
    let castResult4         = cast(*CastValue?, absent)
    Swag.require(castResult4 == null)
}

#test
{
    var value: CastValue
    let itf        = cast(ICastValue, &value)
    let boxed: any = itf
    Swag.require((catch cast(*CastValue?, boxed)) == &value)
    let label = catch cast(ICastLabel?, boxed)
    Swag.require(label != null)
    Swag.require(label.label() == "value")
}

#test
{
    let source = Swag.makeInterface(null, CastValue, ICastValue)
    let target = catch cast(ICastLabel?, source)
    Swag.require(target != null)
    Swag.require(target.label() == "value")
    let castResult5 = catch cast(*CastValue?, source)
    Swag.require(castResult5 == null)
    let absent: *CastValue? = null
    let castResult6         = cast(ICastLabel?, absent)
    Swag.require(castResult6 == null)
}
