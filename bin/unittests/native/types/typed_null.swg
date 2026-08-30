#global private

func typedNullString()->bool
{
    let value = cast(#null string) null
    return value == null and value.count == 0
}

func typedNullSlice()->bool
{
    let value = cast(#null [..] s32) null
    return value == null and value.count == 0
}

func typedNullAny()->bool
{
    let value = cast(#null any) null
    return value == null
}

func typedNullCString()->bool
{
    let value = cast(#null cstring) null
    return value == null and value.count == 0
}

func typedNullConstBytes()->bool
{
    let value = cast(#null const [..] u8) null
    return value == null and value.count == 0
}

func typedNullPointerOrelse()->bool
{
    let value         = cast(#null *s32) null
    var fallback: s32 = 19
    let resolved      = value orelse &fallback
    return value == null and resolved == &fallback and resolved[] == 19
}

func typedNullConditional(flag: bool)->bool
{
    let left          = cast(#null string) null
    let right: string = "ok"
    let resolved      = flag ? left : right
    if flag do
        return resolved == null
    return resolved == "ok"
}

func typedNullSliceConditional(flag: bool)->bool
{
    let left = cast(#null const [..] s32) null
    const storage: [2] s32 = [7, 8]
    let right: const [..] s32 = storage
    let resolved              = flag ? left : right
    if flag do
        return resolved == null and resolved.count == 0
    let vals = resolved!
    return vals.count == 2 and vals[0] == 7 and vals[1] == 8
}

func typedNullDataOf()->bool
{
    let str = cast(#null string) null
    let slc = cast(#null [..] s32) null
    return str.buffer == null and slc.buffer == null
}

#test
{
    Swag.assert(typedNullString())
    Swag.assert(typedNullSlice())
    Swag.assert(typedNullAny())
    Swag.assert(typedNullCString())
    Swag.assert(typedNullConstBytes())
    Swag.assert(typedNullPointerOrelse())
    Swag.assert(typedNullConditional(true))
    Swag.assert(typedNullConditional(false))
    Swag.assert(typedNullSliceConditional(true))
    Swag.assert(typedNullSliceConditional(false))
    Swag.assert(typedNullDataOf())
}
