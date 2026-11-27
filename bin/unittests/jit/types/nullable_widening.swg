#global private

func widenNullablePointer(value: *s32)->*s32?          => value
func widenNullableString(value: string)->string?       => value
func widenNullableSlice(value: [..] s32)->[..] s32?    => value
func widenNullableAny(value: any)->any?                => value
func widenNullableCString(value: cstring)->cstring?    => value
func widenNullableTypeInfo(value: typeinfo)->typeinfo? => value

func nullableWidening()->bool
{
    var storage: s32 = 7
    let ptr = widenNullablePointer(&storage)
    if ptr == null or ptr != &storage
    {
        return false
    }

    let text = widenNullableString("abc")
    if text == null or text.count != 3 or text[1] != 'b'
    {
        return false
    }
    if text != "abc" or "abc" != text
    {
        return false
    }

    let values: [3] s32 = [1, 2, 3]
    let slice = widenNullableSlice(values)
    if slice == null or slice.count != 3 or slice[1] != 2
    {
        return false
    }

    let boxed = widenNullableAny(123)
    if boxed == null or assume cast(s32, boxed) != 123
    {
        return false
    }

    var cstrData: [4] u8 = ['a'_u8, 'b'_u8, 'c'_u8, 0]
    let cstr = widenNullableCString(cast(cstring, &cstrData[0]))
    if cstr == null or cstr.count != 3
    {
        return false
    }

    let infoType: typeinfo = s32
    let info = widenNullableTypeInfo(infoType)
    if info != infoType
    {
        return false
    }

    return true
}

#test
{
    Swag.require(nullableWidening())
}
