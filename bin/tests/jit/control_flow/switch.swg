#global fileprivate // swc-option suite-jit

enum RunSwitchEnum: s32
{
    A = 1
    B = 2
}

#test
{
    func switchScalar(v: s32)->s32
    {
        switch v
        {
            case 1:
                return 11
            case 2, 3:
                return 23
            default:
                return 90
        }
    }

    const V0 = #run switchScalar(1)
    const V1 = #run switchScalar(2)
    const V2 = #run switchScalar(3)
    const V3 = #run switchScalar(9)
    #assert(V0 == 11)
    #assert(V1 == 23)
    #assert(V2 == 23)
    #assert(V3 == 90)
}

#test
{
    func switchFloat(v: f64)->s32
    {
        switch v
        {
            case 1.25:
                return 12
            case 2.5:
                return 25
            default:
                return 0
        }
    }

    const V0 = #run switchFloat(1.25'f64)
    const V1 = #run switchFloat(2.5'f64)
    const V2 = #run switchFloat(8.0'f64)
    #assert(V0 == 12)
    #assert(V1 == 25)
    #assert(V2 == 0)
}

#test
{
    func switchRange(v: s32)->s32
    {
        switch v
        {
            case 1 to 3:
                return 10
            case 4 until 7:
                return 20
            default:
                return 30
        }
    }

    const V0 = #run switchRange(1)
    const V1 = #run switchRange(3)
    const V2 = #run switchRange(4)
    const V3 = #run switchRange(6)
    const V4 = #run switchRange(7)
    #assert(V0 == 10)
    #assert(V1 == 10)
    #assert(V2 == 20)
    #assert(V3 == 20)
    #assert(V4 == 30)
}

#test
{
    func switchWhere(v: s32, takeFirst: bool)->s32
    {
        switch v
        {
            case 1 where takeFirst:
                return 100
            case 1:
                return 200
            default:
                return 300
        }
    }

    const V0 = #run switchWhere(1, true)
    const V1 = #run switchWhere(1, false)
    const V2 = #run switchWhere(2, true)
    #assert(V0 == 100)
    #assert(V1 == 200)
    #assert(V2 == 300)
}

#test
{
    func switchTypeInfo(v: typeinfo)->s32
    {
        switch v
        {
            case s32:
                return 1
            case f64:
                return 2
            case bool:
                return 3
            default:
                return 4
        }
    }

    const T0: typeinfo = s32
    const T1: typeinfo = f64
    const T2: typeinfo = bool
    const T3: typeinfo = string
    const V0 = #run switchTypeInfo(T0)
    const V1 = #run switchTypeInfo(T1)
    const V2 = #run switchTypeInfo(T2)
    const V3 = #run switchTypeInfo(T3)
    #assert(V0 == 1)
    #assert(V1 == 2)
    #assert(V2 == 3)
    #assert(V3 == 4)
}

#test
{
    func switchNoExpr(a: s32, b: s32)->s32
    {
        switch
        {
            case a > b:
                return 10
            case a == b:
                return 20
            default:
                return 30
        }
    }

    const V0 = #run switchNoExpr(5, 1)
    const V1 = #run switchNoExpr(3, 3)
    const V2 = #run switchNoExpr(1, 4)
    #assert(V0 == 10)
    #assert(V1 == 20)
    #assert(V2 == 30)
}

#test
{
    func switchFallthrough(v: s32)->s32
    {
        var r = 0
        switch v
        {
            case 1:
                r = r + 1
                fallthrough
            case 2:
                r = r + 2
                break
            default:
                r = 10
        }

        return r
    }

    const V0 = #run switchFallthrough(1)
    const V1 = #run switchFallthrough(2)
    const V2 = #run switchFallthrough(5)
    #assert(V0 == 3)
    #assert(V1 == 2)
    #assert(V2 == 10)
}

#test
{
    func switchEnum(v: RunSwitchEnum)->s32
    {
        switch v
        {
            case .A:
                return 7
            case .B:
                return 9
        }
    }

    const V0 = #run switchEnum(.A)
    const V1 = #run switchEnum(.B)
    #assert(V0 == 7)
    #assert(V1 == 9)
}

#test
{
    func switchCaseMustBeConst(v: s32)->s32
    {
        switch v
        {
            case v: // swc-expected-error {{sema_err_switch_case_not_const}}
                return 1
            default:
                return 0
        }
    }
}
