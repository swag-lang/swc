struct TypeStructLiteralNativePoint
{
    x: s32
}

func makeTypeStructLiteralPayload() => {first: #type [2] TypeStructLiteralNativePoint, second: #type [3] TypeStructLiteralNativePoint}
func makeTypeStructLiteralPayloads() => [{first: #type [2] TypeStructLiteralNativePoint}, {first: #type [3] TypeStructLiteralNativePoint}]

#test
{
    let payload    = makeTypeStructLiteralPayload()
    let firstInfo  = cast(const *Swag.TypeInfoArray, payload.first)
    let secondInfo = cast(const *Swag.TypeInfoArray, payload.second)

    Swag.require(payload.first == #type [2] TypeStructLiteralNativePoint)
    Swag.require(payload.second == #type [3] TypeStructLiteralNativePoint)
    Swag.require(firstInfo.totalCount == 2)
    Swag.require(secondInfo.totalCount == 3)
}

#test
{
    let payloads   = makeTypeStructLiteralPayloads()
    let firstInfo  = cast(const *Swag.TypeInfoArray, payloads[0].first)
    let secondInfo = cast(const *Swag.TypeInfoArray, payloads[1].first)
    let index      = 1

    Swag.require(payloads[0].first == #type [2] TypeStructLiteralNativePoint)
    Swag.require(payloads[1].first == #type [3] TypeStructLiteralNativePoint)
    Swag.require(payloads[index].first == #type [3] TypeStructLiteralNativePoint)
    Swag.require(firstInfo.totalCount == 2)
    Swag.require(secondInfo.totalCount == 3)
}
