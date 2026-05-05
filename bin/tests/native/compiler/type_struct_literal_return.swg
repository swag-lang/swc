struct TypeStructLiteralNativePoint
{
    x: s32
}

func makeTypeStructLiteralPayload() => {first: #type [2] TypeStructLiteralNativePoint, second: #type [3] TypeStructLiteralNativePoint}

#test
{
    let payload = makeTypeStructLiteralPayload()
    let firstInfo = cast(const *Swag.TypeInfoArray) payload.first
    let secondInfo = cast(const *Swag.TypeInfoArray) payload.second

    @assert(payload.first == #type [2] TypeStructLiteralNativePoint)
    @assert(payload.second == #type [3] TypeStructLiteralNativePoint)
    @assert(firstInfo.totalCount == 2)
    @assert(secondInfo.totalCount == 3)
}
