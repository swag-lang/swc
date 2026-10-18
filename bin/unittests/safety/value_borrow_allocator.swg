#global private
#global #[Swag.Safety(.ValueBorrow, true)]

struct Value { first, second, third: u64 }

#[Swag.NoInline]
func consume(value: Value, other: u64)->u64 => value.first + other

#[Swag.NoInline]
func release(value: *Value)->u64
{
    var request: Swag.AllocatorRequest
    request.address   = value
    request.size      = #sizeof(Value)
    request.callerLoc = #curlocation     // swc-expected-error {{safety_err_runtime}}
    Swag.getContext().allocator!.free(&request)
    return 1
}

#test
{
    #run
    {
        var request: Swag.AllocatorRequest
        request.size = #sizeof(Value)
        Swag.getContext().allocator!.alloc(&request)
        let value = cast(*Value, request.address!)
        value[] = Value{first: 42}
        discard consume(value[], release(value))
    }
}
