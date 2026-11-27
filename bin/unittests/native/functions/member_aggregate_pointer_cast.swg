#global private

func readAggregatePointerMember(flag: bool)->u16
{
    var first  = 70_u16
    var second = 80_u16
    var value  = cast(*void, &second)
    if flag
    {
        value = cast(*void, &first)
    }

    var payload = {ptr: value}
    let data    = cast(*#decltype(payload), &payload)
    let ptr     = cast(const *u16, data.ptr)
    return ptr[]
}

#test
{
    Swag.require(readAggregatePointerMember(true) == 70_u16)
    Swag.require(readAggregatePointerMember(false) == 80_u16)
}
