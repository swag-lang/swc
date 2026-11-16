#global private

// Pointer calls can resolve while the pointed-to declaration is still publishing
// its fields. Keep the forwarding bodies before that declaration.
func forwardDeferredFields(payload: *DeferredFieldPayload)
{
    writeDeferredFields(payload)
}

func writeDeferredFields(payload: *DeferredFieldPayload)
{
    payload.first = 17
    payload.last  = 42
}

struct DeferredFieldPayload
{
    first:   s32
    middleA: s32
    middleB: s32
    middleC: s32
    middleD: s32
    middleE: s32
    middleF: s32
    last:    s32
}

#test
{
    var payload: DeferredFieldPayload
    forwardDeferredFields(&payload)
    Swag.require(payload.first == 17)
    Swag.require(payload.last == 42)
    Swag.require(payload.middleA == 0 and payload.middleF == 0)
}
