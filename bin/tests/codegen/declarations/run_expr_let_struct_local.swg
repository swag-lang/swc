#global fileprivate

struct LocalVarPoint
{
    x: s32
    y: s32
}

struct LocalVarState
{
    enabled: bool = true
    weight: s32 = 5
}

struct LocalVarNode
{
    pos: LocalVarPoint
    state: LocalVarState
}

struct LocalVarPlain
{
    a: s32
    b: bool
    c: u16
}

struct LocalVarRequired
{
    x: s32 = undefined
    y: s32
}

struct LocalVarBig
{
    a0: u64
    a1: u64
    a2: u64
    a3: u64
    a4: u64
    a5: u64
    a6: u64
    a7: u64
    a8: u64
    a9: u64
    a10: u64
    a11: u64
}

struct LocalVarBigDefaults
{
    b0: u64 = 1
    b1: u64 = 3
    b2: u64 = 5
    b3: u64 = 7
    b4: u64 = 11
    b5: u64 = 13
    b6: u64 = 17
    b7: u64 = 19
}

struct LocalVarDirectDefaultNode
{
    p: LocalVarPoint = {x: 9, y: 4}
    state: LocalVarState = {enabled: true, weight: 30}
}

#test
{
    func typedStructInit()->s32
    {
        let p: LocalVarPoint = {x: 4, y: 9}
        return p.x * 10 + p.y
    }

    const V = #run typedStructInit()
    #assert(V == 49)
}

#test
{
    func inferredStructInit()->s32
    {
        let p = LocalVarPoint{x: 7, y: 1}
        return p.x * 10 + p.y
    }

    const V = #run inferredStructInit()
    #assert(V == 71)
}

#test
{
    func nestedStructInit()->s32
    {
        let n: LocalVarNode = {
            pos: {x: 3, y: 8},
            state: {enabled: false, weight: 12},
        }

        if n.state.enabled
        {
            return 0
        }

        return n.pos.x + n.pos.y + n.state.weight
    }

    const V = #run nestedStructInit()
    #assert(V == 23)
}

#test
{
    func structWithDefaults()->s32
    {
        let s: LocalVarState = {weight: 11}
        if s.enabled
        {
            return s.weight
        }

        return 0
    }

    const V = #run structWithDefaults()
    #assert(V == 11)
}

#test
{
    func multiDeclStructVar()->s32
    {
        var a, b: LocalVarPoint = {x: 2, y: 6}
        return a.x * 100 + a.y * 10 + b.x + b.y
    }

    const V = #run multiDeclStructVar()
    #assert(V == 268)
}

#test
{
    func bigStructLiteralInit()->u64
    {
        let v: LocalVarBig = {
            a0: 1,
            a1: 2,
            a2: 3,
            a3: 4,
            a4: 5,
            a5: 6,
            a6: 7,
            a7: 8,
            a8: 9,
            a9: 10,
            a10: 11,
            a11: 12,
        }

        return v.a0 + v.a5 + v.a11
    }

    const V = #run bigStructLiteralInit()
    #assert(V == 19'u64)
}

#test
{
    func bigStructNoInitVar()->u64
    {
        var v: LocalVarBig
        return v.a0 + v.a6 + v.a11
    }

    const V = #run bigStructNoInitVar()
    #assert(V == 0'u64)
}

#test
{
    func bigStructDefaultsAll()->u64
    {
        let v: LocalVarBigDefaults = {}
        return v.b0 + v.b4 + v.b7
    }

    const V = #run bigStructDefaultsAll()
    #assert(V == 31'u64)
}

#test
{
    func bigStructDefaultsPartial()->u64
    {
        let v: LocalVarBigDefaults = {b1: 100, b6: 200}
        return v.b0 + v.b1 + v.b6 + v.b7
    }

    const V = #run bigStructDefaultsPartial()
    #assert(V == 320'u64)
}

#test
{
    func aggregateDefaultsFromFieldDecl()->s32
    {
        let n: LocalVarDirectDefaultNode = {}
        if n.state.enabled
        {
            return n.p.x + n.p.y + n.state.weight
        }

        return 0
    }

    const V = #run aggregateDefaultsFromFieldDecl()
    #assert(V == 43)
}
