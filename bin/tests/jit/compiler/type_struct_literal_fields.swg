struct TypeStructLiteralJitPoint
{
    x: s32
}

#test
{
    let payload = {first: #type [2] TypeStructLiteralJitPoint, second: #type [3] TypeStructLiteralJitPoint}

    #assert(#typeof(payload.first) == const *TypeInfoArray)
    @assert(payload.first == #type [2] TypeStructLiteralJitPoint)
    @assert(payload.second == #type [3] TypeStructLiteralJitPoint)
    @assert(payload.first.totalCount == 2)
}

#test
{
    let payloads = [{first: #type [2] TypeStructLiteralJitPoint}, {first: #type [3] TypeStructLiteralJitPoint}]

    #assert(#typeof(payloads[0].first) == const *TypeInfoArray)
    @assert(payloads[0].first == #type [2] TypeStructLiteralJitPoint)
    @assert(payloads[1].first == #type [3] TypeStructLiteralJitPoint)
}
