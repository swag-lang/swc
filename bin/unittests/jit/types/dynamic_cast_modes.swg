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
    let view = cast(ICastValue) value
    return view.value()
}

#test
{
    var value: CastValue
    let itf      = cast(ICastValue) &value
    let concrete = cast #try (*CastValue) itf
    Swag.assert(concrete == &value)
    let castResult1 = cast #try (*OtherCastValue) itf
    Swag.assert(castResult1 == null)
    Swag.assert(cast #assume (*CastValue) itf == &value)
    let label = cast #try (ICastLabel) itf
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
    Swag.assert(cast #try (*CastValue) boxed == &value)
    let castResult2 = cast #try (*OtherCastValue) boxed
    Swag.assert(castResult2 == null)
    let view = cast #try (ICastValue) boxed
    if view != null do
        Swag.assert(view.value() == 42)
    Swag.assert(view != null)
}

#test
{
    var boxed: any = 17's32
    let value      = cast #try (*s32) boxed
    if value != null do
        Swag.assert(value[] == 17)
    Swag.assert(value != null)
    let castResult3 = cast #try (*s64) boxed
    Swag.assert(castResult3 == null)
    Swag.assert(cast #assume (s32) boxed == 17)
}

#assert(CastValue is ICastValue)
#assert(not (OtherCastValue is ICastValue))
#assert(not (s32 is ICastValue))

#test
{
    var value:    CastValue
    let readOnly: const *CastValue = &value
    let boxed:    const any        = readOnly
    Swag.assert(cast #try (const *CastValue) boxed == readOnly)
    let absent: *CastValue? = null
    let castResult4         = cast #try (*CastValue) absent
    Swag.assert(castResult4 == null)
}

#test
{
    var value: CastValue
    let itf        = cast(ICastValue) &value
    let boxed: any = itf
    Swag.assert(cast #try (*CastValue) boxed == &value)
    let label = cast #try (ICastLabel) boxed
    Swag.assert(label != null)
    Swag.assert(label.label() == "value")
}

#test
{
    let source = Swag.makeInterface(null, CastValue, ICastValue)
    let target = cast #try (ICastLabel) source
    Swag.assert(target != null)
    Swag.assert(target.label() == "value")
    let castResult5 = cast #try (*CastValue) source
    Swag.assert(castResult5 == null)
    let absent: *CastValue? = null
    let castResult6         = cast #try (ICastLabel) absent
    Swag.assert(castResult6 == null)
}
