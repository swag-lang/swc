#global fileprivate

func takesType(t: typeinfo)->bool
{
    return t != null
}

func(T) takesGenericType()->bool
{
    return takesType(T)
}

func semaTest001()
{
    @assert(takesType(s32))
    @assert(takesType(#type s32))
    @assert(takesGenericType's32())
}
