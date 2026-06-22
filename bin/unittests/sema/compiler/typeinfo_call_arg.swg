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

#[Swag.Inline]
func takesType1(t: typeinfo)->bool
{
    return t != null
}

func(T) takesGenericType1()->bool
{
    return takesType1(T)
}

func semaTest002()
{
    @assert(takesType1(s32))
    @assert(takesType1(#type s32))
    @assert(takesGenericType1's32())
}
