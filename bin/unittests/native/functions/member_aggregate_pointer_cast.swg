#global private

func readAggregatePointerMember(flag: bool)->u16
{
    var first  = 70'u16
    var second = 80'u16
    var value  = cast(*void) &second
    if flag do
        value = cast(*void) &first

    var payload = {ptr: value}
    let data    = cast(*#decltype(payload)) &payload
    let ptr     = cast(const *u16) data.ptr
    return dref ptr
}

#test
{
    @assert(readAggregatePointerMember(true) == 70'u16)
    @assert(readAggregatePointerMember(false) == 80'u16)
}
