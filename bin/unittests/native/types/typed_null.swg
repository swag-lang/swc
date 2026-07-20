#global private

func typedNullString()->bool
{
    let value = cast(#null string) null
    return value == null and @countof(value) == 0
}

func typedNullSlice()->bool
{
    let value = cast(#null [..] s32) null
    return value == null and @countof(value) == 0
}

func typedNullAny()->bool
{
    let value = cast(#null any) null
    return value == null
}

func typedNullCString()->bool
{
    let value = cast(#null cstring) null
    return value == null and @countof(value) == 0
}

func typedNullConstBytes()->bool
{
    let value = cast(#null const [..] u8) null
    return value == null and @countof(value) == 0
}

func typedNullPointerOrelse()->bool
{
    let value = cast(#null *s32) null
    var fallback: s32 = 19
    let resolved = value orelse &fallback
    return value == null and resolved == &fallback and dref resolved == 19
}

func typedNullConditional(flag: bool)->bool
{
    let left = cast(#null string) null
    let right: string = "ok"
    let resolved = flag ? left : right
    if flag do
        return resolved == null
    return resolved == "ok"
}

func typedNullSliceConditional(flag: bool)->bool
{
    let left = cast(#null const [..] s32) null
    const storage: [2] s32 = [7, 8]
    let right: const [..] s32 = storage
    let resolved = flag ? left : right
    if flag do
        return resolved == null and @countof(resolved) == 0
    return @countof(resolved) == 2 and resolved[0] == 7 and resolved[1] == 8
}

func typedNullDataOf()->bool
{
    let str = cast(#null string) null
    let slc = cast(#null [..] s32) null
    return @dataof(str) == null and @dataof(slc) == null
}

#test
{
    @assert(typedNullString())
    @assert(typedNullSlice())
    @assert(typedNullAny())
    @assert(typedNullCString())
    @assert(typedNullConstBytes())
    @assert(typedNullPointerOrelse())
    @assert(typedNullConditional(true))
    @assert(typedNullConditional(false))
    @assert(typedNullSliceConditional(true))
    @assert(typedNullSliceConditional(false))
    @assert(typedNullDataOf())
}
