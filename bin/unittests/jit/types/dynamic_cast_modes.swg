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
    Swag.require(value == null)
    Swag.require(catch cast(const *s32?, boxed) != null)
    let castResult3 = catch cast(*s64?, boxed)
    Swag.require(castResult3 == null)
    Swag.require(assume cast (s32, boxed) == 17)
}

// Constant-backed any values stay readable and cannot lend mutable storage.
#test
{
    var literalBox: any = 42's32
    Swag.require(Swag.kindOf(literalBox) == s32)
    Swag.require((catch cast(*s32?, literalBox)) == null)
    Swag.require(catch cast(const *s32?, literalBox) != null)
    if literalBox is s32 as number do
        number[] = 0
    Swag.require(assume cast(s32, literalBox) == 42)

    const value: s32 = 43
    var constantBox: any = value
    Swag.require(Swag.kindOf(constantBox) == s32)
    Swag.require((catch cast(*s32?, constantBox)) == null)
    Swag.require(catch cast(const *s32?, constantBox) != null)
    Swag.require(assume cast(s32, constantBox) == 43)

    var recordBox: any = CastValue{number: 46}
    Swag.require(Swag.kindOf(recordBox) == CastValue)
    Swag.require((catch cast(*CastValue?, recordBox)) == null)
    let recordValue = catch cast(const *CastValue?, recordBox)
    Swag.require(recordValue != null)
    if recordValue != null do
        Swag.require(recordValue[].number == 46)
    var recordCopy = assume cast(CastValue, recordBox)
    recordCopy.number = 47
    Swag.require(recordCopy.number == 47)
    if recordValue != null do
        Swag.require(recordValue[].number == 46)
}

// A mutable local remains writable through the same dynamic cast.
#test
{
    var value: s32 = 44
    var boxed: any = value
    let pointer = catch cast(*s32?, boxed)
    Swag.require(pointer != null)
    pointer[] = 45
    Swag.require(value == 45)
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
