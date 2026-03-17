#global fileprivate // 

struct FuncData
{
    base:  s32
    delta: s32
}

alias Transform = func(FuncData, s32)->s32
alias Reducer = func(s32...)->s32

struct TransformHolder
{
    cb: Transform
}

func addTransform(data: FuncData, extra: s32)->s32
{
    return data.base + data.delta + extra
}

func scaleTransform(data: FuncData, extra: s32)->s32
{
    return data.base * extra + data.delta
}

func sumReducer(values: s32...)->s32
{
    var result = 0
    foreach value in values do
        result += value
    return result
}

func weightedReducer(values: s32...)->s32
{
    var result = 0
    foreach value, index in values do
        result += value * (cast(s32) index + 1)
    return result
}

func applyTransform(cb: Transform, data: FuncData, extra: s32)->s32
{
    return cb(data, extra)
}

#test
{
    let direct: Transform = &addTransform
    let alternate: Transform = &scaleTransform

    var holder: TransformHolder = {cb: &addTransform}
    var callbacks: [2] Transform
    callbacks[0] = &addTransform
    callbacks[1] = alternate

    @assert(direct({base: 10, delta: 2}, 3) == 15)
    @assert(alternate({base: 10, delta: 2}, 3) == 32)
    @assert(holder.cb({base: 1, delta: 4}, 8) == 13)
    @assert(callbacks[0]({base: 5, delta: -1}, 2) == 6)
    @assert(callbacks[1]({base: 5, delta: -1}, 2) == 9)
    @assert(applyTransform(direct, {base: 7, delta: 1}, 4) == 12)
}

#test
{
    let reduce: Reducer = &sumReducer
    var reducers: [2] Reducer
    reducers[0] = reduce
    reducers[1] = &weightedReducer

    @assert(reduce(1, 2, 3, 4) == 10)
    @assert(reducers[0](5, 6, 7) == 18)
    @assert(reducers[1](2, 3, 4) == 20)
}
