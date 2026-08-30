struct TypeStructLiteralJitPoint
{
    x: s32
}

func makeTypeStructLiteralJitPayloads() => [{first: #type [2] TypeStructLiteralJitPoint}, {first: #type [3] TypeStructLiteralJitPoint}]

#test
{
    let payload = {first: #type [2] TypeStructLiteralJitPoint, second: #type [3] TypeStructLiteralJitPoint}

    #assert(#typeof(payload.first) == const *TypeInfoArray)
    Swag.assert(payload.first == #type [2] TypeStructLiteralJitPoint)
    Swag.assert(payload.second == #type [3] TypeStructLiteralJitPoint)
    Swag.assert(payload.first.totalCount == 2)
}

#test
{
    let payloads = [{first: #type [2] TypeStructLiteralJitPoint}, {first: #type [3] TypeStructLiteralJitPoint}]

    #assert(#typeof(payloads[0].first) == const *TypeInfoArray)
    Swag.assert(payloads[0].first == #type [2] TypeStructLiteralJitPoint)
    Swag.assert(payloads[1].first == #type [3] TypeStructLiteralJitPoint)
}

#test
{
    let payloads   = makeTypeStructLiteralJitPayloads()
    var total: u64 = 0
    for payload in payloads
    {
        total += (cast(const *Swag.TypeInfoArray) payload.first).totalCount
    }

    Swag.assert(total == 5)
}
