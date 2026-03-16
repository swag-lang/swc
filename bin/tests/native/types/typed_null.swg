#global fileprivate // swc-option suite-test

func typedNullString()->bool
{
    let value = cast(string) null
    return value == null and @countof(value) == 0
}

func typedNullSlice()->bool
{
    let value = cast([..] s32) null
    return value == null and @countof(value) == 0
}

func typedNullAny()->bool
{
    let value = cast(any) null
    return value == null
}

func typedNullConstBytes()->bool
{
    let value = cast(const [..] u8) null
    return value == null and @countof(value) == 0
}

func typedNullPointerOrelse()->bool
{
    let value = cast(*s32) null
    var fallback: s32 = 19
    let resolved = value orelse &fallback
    return value == null and resolved == &fallback and dref resolved == 19
}

func typedNullConditional(flag: bool)->bool
{
    let left = cast(string) null
    let right: string = "ok"
    let resolved = flag ? left : right
    if flag do
        return resolved == null
    return resolved == "ok"
}

#test
{
    @assert(typedNullString())
    @assert(typedNullSlice())
    @assert(typedNullAny())
    @assert(typedNullConstBytes())
    @assert(typedNullPointerOrelse())
    @assert(typedNullConditional(true))
    @assert(typedNullConditional(false))
}
