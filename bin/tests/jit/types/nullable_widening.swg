#global fileprivate

func widenNullablePointer(value: *s32)->#null *s32 => value
func widenNullableString(value: string)->#null string => value
func widenNullableSlice(value: [..] s32)->#null [..] s32 => value
func widenNullableAny(value: any)->#null any => value
func widenNullableCString(value: cstring)->#null cstring => value
func widenNullableTypeInfo(value: typeinfo)->#null typeinfo => value

func nullableWidening()->bool
{
    var storage: s32 = 7
    let ptr = widenNullablePointer(&storage)
    if ptr == null or ptr != &storage do
        return false

    let text = widenNullableString("abc")
    if text == null or @countof(text) != 3 or text[1] != 'b' do
        return false

    let values: [3] s32 = [1, 2, 3]
    let slice = widenNullableSlice(values)
    if slice == null or @countof(slice) != 3 or slice[1] != 2 do
        return false

    let boxed = widenNullableAny(123)
    if boxed == null or cast(s32) boxed != 123 do
        return false

    let cstr = widenNullableCString(cast(cstring) @dataof("abc"))
    if cstr == null or @countof(cstr) != 3 do
        return false

    let infoType: typeinfo = s32
    let info = widenNullableTypeInfo(infoType)
    if info != infoType do
        return false

    return true
}

#test
{
    @assert(nullableWidening())
}
