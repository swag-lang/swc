#global private

struct MixinClosurePayload
{
    values: [3] s32
    bias:   s32
}

#[Swag.Mixin]
func mixinPayloadClosure(payload: MixinClosurePayload)->s32
{
    let payloadCb = func|payload|()->s32
    {
        return payload.values[1] + payload.bias
    }

    return payloadCb()
}

#test
{
    @assert(mixinPayloadClosure(MixinClosurePayload{[10, 20, 30], 4}) == 24)
}
