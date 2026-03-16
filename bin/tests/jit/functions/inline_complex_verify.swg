#global fileprivate // swc-option suite-jit

struct Payload
{
    values: [3] s32
    tag: u8
}

#[Swag.Inline]
func inlinePayloadEcho(payload: Payload)->Payload => payload

func failInlinePayloadAssert()->u8
{
    var pay = inlinePayloadEcho(Payload{[20, 21, 22], 2})
    @assert(pay.values[0] == 20)
    @assert(pay.values[1] == 21)
    @assert(pay.values[2] == 22)
    @assert(pay.tag == 2)
    @assert(pay.tag == 3) // swc-expected-error {{sema_err_assert_failed}}
    return pay.tag
}

#test
{
    const V = #run failInlinePayloadAssert()
    @assert(V == 2)
}
