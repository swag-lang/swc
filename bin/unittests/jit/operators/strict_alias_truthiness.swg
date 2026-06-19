#global fileprivate

#[Swag.Strict]
alias Handle = const *void

func runtimeHandleTruthy()->bool
{
    var value: s32 = 1
    let handle = cast(Handle) &value
    if !handle do
        return false

    let asAnd = handle and true
    let asOr = handle or false
    return handle != null and asAnd and asOr
}

func runtimeHandleNull()->bool
{
    let handle = cast(Handle) null
    let asAnd = handle and true
    let asOr = handle or false
    return !handle and handle == null and !(handle != null) and !asAnd and !asOr
}

func runtimeHandleOrelseNonNull()->bool
{
    var first: s32 = 1
    var second: s32 = 2
    let primary = cast(Handle) &first
    let fallback = cast(Handle) &second
    let resolved = primary orelse fallback
    #assert(#typeof(resolved) == Handle)
    return resolved == primary and resolved != fallback
}

func runtimeHandleOrelseFallback()->bool
{
    var value: s32 = 3
    let fallback = cast(Handle) &value
    let resolved = cast(Handle) null orelse fallback
    #assert(#typeof(resolved) == Handle)
    return resolved == fallback and resolved != null
}

#test
{
    const V = #run runtimeHandleTruthy()
    #assert(V)
}

#test
{
    const V = #run runtimeHandleNull()
    #assert(V)
}

#test
{
    const V = #run runtimeHandleOrelseNonNull()
    #assert(V)
}

#test
{
    const V = #run runtimeHandleOrelseFallback()
    #assert(V)
}
